variable "common_tags" {
  default = {}
}

variable "region" {
  description = "The region the eks cluster will be deployed"


}
variable "cluster_name" {
  description = "Cluster name"
}

variable "aws_account_id" {
  description = "The ID of the account the cluster will belong to"

}

variable "host_zone_id" {
  description = "Host zone ID of route 53"
}

variable "base_domain" {
  description = "the domain name that eks will control"

}
variable "cert_issuer" {
  default     = "letsencrypt"
  description = "The TLS certificate issuer"
}

variable "cert_email" {
  description = "Contact person email to be set with the TLS certificate"
}