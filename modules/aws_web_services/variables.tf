variable "cluster_endpoint" {

}

variable "cluster_ca_certificate" {

}

variable "cluster_name" {}

variable "aws_account_id" {}

variable "cluster_oidc_issuer_url" {}

variable "cluster_id" {}

variable "base_domain" {}

variable "host_zone_id" {}

variable "cert_issuer" {}

variable "cert_email" {}

variable "region" {}

variable "aws_iam_policy_document_json" {
  type    = string
  default = "{}"
}

variable "external_dns_helm_values_template" {}

#variable "cert_manager_template" {}

variable "traefik_helm_values_file" {}

#variable "traefik_dashboard_manifest_file" {}

variable "cert_manager_helm_values_file" {

}

variable "lets_encrypt_issuer_manifests" {
  type = map(any)
}

variable "traefik_dashboard_manifests" {
  type = map(any)
}

variable "eks_admin_manifests" {
  type = map(any)
}