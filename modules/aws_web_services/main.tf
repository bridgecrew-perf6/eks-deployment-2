################################################################################################################
# DEPLOYING CORE web services
################################################################################################################


# 
# SET PROVISIONERS CONFIGURATION
#

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.cluster_name
    ]
  }

}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        var.cluster_name
      ]
    }
  }
}


#
# EKS ADMIN 
#

resource "kubectl_manifest" "eks_admin" {
  for_each  = var.eks_admin_manifests
  yaml_body = each.value
}

#module "eks_admin" {
#  source = "../kubectl-file"
#  file   = "./data/eks-admin-service-account.yaml"
#}



#
# DASHBOARD
#

resource "kubernetes_namespace" "kubernetes-dashboard" {
  metadata {
    name = "kubernetes-dashboard"
  }
}


resource "kubernetes_secret" "admin_user" {
  metadata {
    name      = "admin-user"
    namespace = "kubernetes-dashboard"
  }

  depends_on = [kubectl_manifest.eks_admin]
}


resource "kubernetes_service_account" "admin_user" {
  metadata {
    name      = "admin-user"
    namespace = "kubernetes-dashboard"
  }

  secret {
    name = kubernetes_secret.admin_user.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "admin_user" {
  metadata {
    name = "admin-user"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "User"
    name      = "admin"
    namespace = "kubernetes-dashboard"
    api_group = "rbac.authorization.k8s.io"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "admin-user"
    namespace = "kubernetes-dashboard"
  }
  subject {
    kind      = "Group"
    name      = "system:masters"
    api_group = "rbac.authorization.k8s.io"
  }


}


resource "helm_release" "dashboard" {
  name       = "kubernetes-dashboard"
  repository = "https://kubernetes.github.io/dashboard/"
  chart      = "kubernetes-dashboard"
  namespace  = "kubernetes-dashboard"

  depends_on = [
    kubernetes_service_account.admin_user,
    kubernetes_namespace.kubernetes-dashboard,
  ]

  set {
    name  = "fullnameOverride"
    value = "kubernetes-dashboard"
  }

  set {
    name  = "serviceAccount.create"
    value = false
  }

  set {
    name  = "serviceAccount.name"
    value = "admin-user"
  }

  set {
    name  = "metricsScraper.enabled"
    value = true
  }

  set {
    name  = "metrics-server.enabled"
    value = true
  }

  set {
    name  = "protocolHttp"
    value = true
  }
}



#
#  EXTERNAL DNS deployment
#


locals {
  external_dns_eks_namespace = "external-dns"
}



resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = local.external_dns_eks_namespace
  }

}

module "external_dns_eks_iam_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "0.7.1"

  name = "external-dns-${var.cluster_id}"

  aws_account_number          = var.aws_account_id
  eks_cluster_oidc_issuer_url = var.cluster_oidc_issuer_url
  service_account_name        = var.cluster_id
  service_account_namespace   = local.external_dns_eks_namespace
  aws_iam_policy_document     = var.aws_iam_policy_document_json
  depends_on                  = [kubernetes_namespace.external_dns]

}

resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = module.external_dns_eks_iam_role.service_account_name
    namespace = module.external_dns_eks_iam_role.service_account_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" : module.external_dns_eks_iam_role.service_account_role_arn
    }
  }
}


resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  namespace  = module.external_dns_eks_iam_role.service_account_namespace

  timeout = "300"

  values = [templatefile(var.external_dns_helm_values_template, {
    serviceAccountName : module.external_dns_eks_iam_role.service_account_name
    domain : var.base_domain
    hostZoneID : var.host_zone_id
    }),
    jsonencode({
      nodeSelector = {
        arch = "amd64"
      }
    })
  ]
  depends_on = [
    kubectl_manifest.eks_admin
  ]
}





############
## CERT MANAGER
############
locals {
  cert_manager_namespace = "cert-manager"
}
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = local.cert_manager_namespace
  }
}

#Install cert manager CRD
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = kubernetes_namespace.cert_manager.metadata[0].name
  version          = "v1.7.2"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = true
  }

  set {
    name  = "serviceAccount.create"
    value = false
  }

  set {
    name  = "serviceAccount.name"
    value = module.cert_manager_eks_iam_role.service_account_name
  }

  set {
    name  = "prometheus.enabled"
    value = false
  }

  set {
    name  = "webhook.timeoutSeconds"
    value = 4
  }

  values = [
    jsonencode({
      nodeSelector = {
        arch = "amd64"
      }
    })
    # file(var.cert_manager_helm_values_file)  
  ]
}


data "aws_iam_policy_document" "cert_manager" {
  statement {
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
    effect    = "Allow"
  }
  statement {
    actions   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/*"]
    effect    = "Allow"
  }
  statement {
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
    effect    = "Allow"
  }
}


module "cert_manager_eks_iam_role" {
  source  = "cloudposse/eks-iam-role/aws"
  version = "0.7.1"

  name = "cert-manager-${var.cluster_id}"

  aws_account_number          = var.aws_account_id
  eks_cluster_oidc_issuer_url = var.cluster_oidc_issuer_url
  service_account_name        = "cert-manager"
  service_account_namespace   = kubernetes_namespace.cert_manager.metadata[0].name
  aws_iam_policy_document     = data.aws_iam_policy_document.cert_manager.json
}

resource "kubernetes_service_account" "cert_manager" {
  metadata {
    name      = module.cert_manager_eks_iam_role.service_account_name
    namespace = module.cert_manager_eks_iam_role.service_account_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" : module.cert_manager_eks_iam_role.service_account_role_arn
    }
  }
}


resource "kubectl_manifest" "lets_encrypt_issuer" {
  for_each  = var.lets_encrypt_issuer_manifests
  yaml_body = each.value
}

# module "lets_encrypt_issuer" {
#   source = "../kubectl-template"
#   file   = var.cert_manager_template
#   values = {
#     certIssuer   = var.cert_issuer
#     email        = var.cert_email
#     region       = var.region
#     hostedZoneID = var.host_zone_id
#   }
# }



## TRAEFIK
resource "helm_release" "traefik" {
  chart            = "traefik"
  repository       = "https://helm.traefik.io/traefik"
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  values           = [file(var.traefik_helm_values_file)]

  depends_on = [
    kubectl_manifest.eks_admin
  ]
}

resource "kubectl_manifest" "traefik_dashboard_manifest" {
  for_each  = var.traefik_dashboard_manifests
  yaml_body = each.value
}


# module "traefik_dashboard_manifest" {
#   source = "../kubectl-file"
#   file   = var.traefik_dashboard_manifest_file
#   depends_on = [
#     helm_release.traefik
#   ]
# }
