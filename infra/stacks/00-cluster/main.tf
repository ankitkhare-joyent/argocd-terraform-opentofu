# Layer 00: the cluster itself.
#
# Why its own stack? Different blast radius and change rate. You rebuild
# in-cluster things often, but you almost never want a typo there to plan a
# cluster replacement. Separate state per layer is the standard way to keep
# those apart.

locals {
  # All ports bind to 127.0.0.1 only. Chosen high to avoid clashing with
  # anything else running on the laptop.
  port_mappings = {
    argocd  = { node_port = 30080, host_port = 48080 }
    openbao = { node_port = 30820, host_port = 48200 }
  }
}

module "cluster" {
  source = "../../modules/kind-cluster"

  name            = var.cluster_name
  node_image      = var.node_image
  kubeconfig_path = abspath("${path.root}/../../../.kube/config")
  worker_count    = 0
  port_mappings   = local.port_mappings
}
