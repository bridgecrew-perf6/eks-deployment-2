output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_region" {
  value = var.region
}

output "eks_id" {
  value = module.eks.cluster_id
}

output "eks_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "eks" {
  value = module.eks
}

output "aws_eks_cluster" {
  value = data.aws_eks_cluster.cluster
}

output "aws_eks_auth" {
  value     = data.aws_eks_cluster_auth.cluster
  sensitive = true
}

output "autoscaler_manifest" {
  value = data.kubectl_file_documents.autoscaler_docs.manifests
}

output "cert_manager_manifest" {
  value = data.kubectl_file_documents.lets_encrypt_docs.manifests
}

output "traefik_dashboard_manifest" {
  value = data.kubectl_file_documents.traefik_dashboard_docs.manifests
}

output "eks_web_services" {
  value     = module.eks_web_services
  sensitive = true
}
