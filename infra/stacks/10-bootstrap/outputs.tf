output "argocd_url" {
  value = "http://localhost:48080"
}

output "argocd_chart_version" {
  value = module.argocd.chart_version
}

output "next_step" {
  value = "Watch Argo CD sync the platform: kubectl -n argocd get applications -w"
}
