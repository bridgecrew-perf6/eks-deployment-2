
output "dashboard" {
  value     = helm_release.dashboard
  sensitive = true
}

output "external-dns-role" {
  value = module.external_dns_eks_iam_role
}


output "external-dns" {
  value     = helm_release.external_dns
  sensitive = true
}

output "cert-manager" {
  value     = helm_release.cert_manager
  sensitive = true
}

output "traefik" {
  value     = helm_release.traefik
  sensitive = true
}

