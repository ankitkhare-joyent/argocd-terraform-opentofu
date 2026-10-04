output "kubeconfig_path" {
  value = module.cluster.kubeconfig_path
}

output "kube_context" {
  value = module.cluster.kube_context
}

output "endpoint" {
  value = module.cluster.endpoint
}
