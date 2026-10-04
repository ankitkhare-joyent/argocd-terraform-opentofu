# A local Kubernetes cluster that stands in for a managed cluster (EKS, GKE, AKS).
#
# In production this module would wrap something like terraform-aws-modules/eks:
# VPC, node groups, IAM roles for service accounts, and so on. The *interface*
# (name in, kubeconfig/endpoint out) is what the rest of the platform depends on,
# so swapping kind for EKS later only changes this module, not the stacks above it.

resource "kind_cluster" "this" {
  name            = var.name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = var.kubeconfig_path

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Each mapping exposes a NodePort on your Mac so you can reach the service
      # without `kubectl port-forward`. In a cloud cluster this is an Ingress or
      # a LoadBalancer instead.
      dynamic "extra_port_mappings" {
        for_each = var.port_mappings
        content {
          container_port = extra_port_mappings.value.node_port
          host_port      = extra_port_mappings.value.host_port
          listen_address = "127.0.0.1"
          protocol       = "TCP"
        }
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}
