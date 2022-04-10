
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "eks-${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]

  tags = var.common_tags
}


resource "aws_security_group" "eks_inner_comm" {
  name        = "eks-inner-comm"
  description = "Allow inner communication between all EKS nodes"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port = 0
    protocol  = "-1"
    to_port   = 0
    self      = true
  }
  egress {
    from_port = 0
    protocol  = "-1"
    to_port   = 0
    self      = true
  }
  tags = merge({
    Name = "eks-inner-comm"
  }, var.common_tags)
}

locals {
  k8s_version="1.22"
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name                    = var.cluster_name
  cluster_version                 = local.k8s_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  enable_irsa = true

  cluster_enabled_log_types = []

  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = concat(module.vpc.public_subnets, module.vpc.private_subnets)


  node_security_group_additional_rules = {
    outbount_53 = {
      type        = "egress",
      from_port   = 53
      to_port     = 53
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type               = "AL2_x86_64"
    instance_types         = ["t3a.medium"]
    vpc_security_group_ids = [aws_security_group.eks_inner_comm.id]
    labels = {
      Environment = var.cluster_name
    }
    tags = var.common_tags
    workers_additional_policies = [
      "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
    ]
    workers_group_defaults = {
      root_volume_type = "gp2"
    }

  }

  eks_managed_node_groups = {
    amd64-grp-1 = {
      ami_type     = "AL2_x86_64"
      min_size     = 1
      max_size     = 5
      desired_size = 1

      instance_types = ["t3a.medium"]
      capacity_type  = "ON_DEMAND"

      labels = {
        Environment = var.cluster_name
        arch        = "amd64"
      }
      tags = merge({
        "Name"                                          = "eks-${var.cluster_name}-amd64"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
        "k8s.io/cluster-autoscaler/enabled"             = "TRUE"
      }, var.common_tags)
      cluster_timeouts = {
        create = "8m"
        delete = "8m"
      }
    # },
    # arm64-grp-1 = {
    #   ami_type     = "AL2_ARM_64"
    #   min_size     = 1
    #   max_size     = 5
    #   desired_size = 1
    #   cluster_timeouts = {
    #     create = "8m"
    #     delete = "8m"
    #   }
    #   instance_types = ["a1.large"]
    #   capacity_type  = "ON_DEMAND"

    #   labels = {
    #     Environment = var.cluster_name
    #     arch        = "arm64"
    #   }
    #   tags = merge({
    #     "Name"                                          = "eks-${var.cluster_name}-arm64"
    #     "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    #     "k8s.io/cluster-autoscaler/enabled"             = "TRUE"
    #   }, var.common_tags)
    # }

  }

  tags = var.common_tags
}

resource "aws_iam_policy" "eks_allow_autoscale" {
  name        = "foodsager-eks-allow-autoscale"
  description = "Allow cluster autoscale"
  policy      = file("./data/policy_allow_eks_autoscale.json")
}


resource "aws_iam_policy" "eks_node_policy" {
  depends_on = [
    module.eks
  ]
  name        = "eks-playground-node-policy"
  description = "Allow attach of volumes"
  policy      = file("./data/eks_node_policy.json")
}


resource "aws_iam_role_policy_attachment" "general_role_policy_attachment" {
  for_each   = module.eks.eks_managed_node_groups
  role       = each.value.iam_role_name
  policy_arn = aws_iam_policy.eks_node_policy.arn
}

resource "aws_iam_role_policy_attachment" "autoscaling_role_policy_attachment" {
  for_each   = module.eks.eks_managed_node_groups
  role       = each.value.iam_role_name
  policy_arn = aws_iam_policy.eks_allow_autoscale.arn
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}


data "aws_iam_policy_document" "external_dns_playground" {
  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/*"]
    effect    = "Allow"
  }
  statement {
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets"]
    resources = ["*"]
    effect    = "Allow"
  }
}


provider "kubectl" {
  apply_retry_count      = 3
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      data.aws_eks_cluster.cluster.name
    ]
  }
}

data template_file "autoscaler_template"{
  template = file("./data/cluster-autoscaler-autodiscover.tpl.yaml")
  vars={
    clusterName=data.aws_eks_cluster.cluster.name
    eks_version=local.k8s_version
  }
}


data "template_file" "lets_encrypt_manifest_template" {
  template = file("./data/cert-manager.tpl.yaml")
  vars = {
    certIssuer   = var.cert_issuer
    email        = var.cert_email
    region       = var.region
    hostedZoneID = var.host_zone_id
  }
}

resource "null_resource" "step_1" {
  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.general_role_policy_attachment,
    aws_iam_role_policy_attachment.autoscaling_role_policy_attachment,
    data.aws_eks_cluster.cluster,
    data.aws_eks_cluster_auth.cluster,
    data.aws_iam_policy_document.external_dns_playground,
    data.template_file.autoscaler_template,
    data.template_file.lets_encrypt_manifest_template,
    
  ]
  triggers = {
    bumper = 1
  }
}

data "kubectl_file_documents" "autoscaler_docs" {
  content = data.template_file.autoscaler_template.rendered
}


resource "kubectl_manifest" "autoscaler" {
  for_each  = data.kubectl_file_documents.autoscaler_docs.manifests
  yaml_body = each.value
}


data "kubectl_file_documents" "lets_encrypt_docs" {
  content = data.template_file.lets_encrypt_manifest_template.rendered
}


data "kubectl_file_documents" "traefik_dashboard_docs" {
  content = file("./data/traefik-dashboard.yaml")
}


data "kubectl_file_documents" "eks_admin_docs" {
  content = file("./data/eks-admin-service-account.yaml")
}

resource "null_resource" "step_2" {
  depends_on = [
    null_resource.step_1,
    data.kubectl_file_documents.autoscaler_docs,
    data.kubectl_file_documents.lets_encrypt_docs,
    data.kubectl_file_documents.traefik_dashboard_docs,
    data.kubectl_file_documents.eks_admin_docs
  ]
  triggers = {
    bumper = 1
  }
}

module "eks_web_services" {
  source                  = "./modules/aws_web_services"
  cluster_endpoint        = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate  = data.aws_eks_cluster.cluster.certificate_authority.0.data
  cluster_name            = data.aws_eks_cluster.cluster.name
  aws_account_id          = var.aws_account_id
  cluster_id              = module.eks.cluster_id
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  base_domain             = var.base_domain
  host_zone_id            = var.host_zone_id
  cert_email              = var.cert_email
  cert_issuer             = var.cert_issuer
  region                  = var.region

  cert_manager_helm_values_file = "./data/cert-manager-helm-values.yaml"

  eks_admin_manifests               = data.kubectl_file_documents.eks_admin_docs.manifests
  aws_iam_policy_document_json      = data.aws_iam_policy_document.external_dns_playground.json
  external_dns_helm_values_template = "./data/external-dns-helm-values.tpl.yaml"
  lets_encrypt_issuer_manifests     = data.kubectl_file_documents.lets_encrypt_docs.manifests

  traefik_helm_values_file    = "./data/traefik-helm-values.yaml"
  traefik_dashboard_manifests = data.kubectl_file_documents.traefik_dashboard_docs.manifests
}
