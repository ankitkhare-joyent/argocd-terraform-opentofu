# Both providers talk to the cluster built by stack 00 through the kubeconfig
# file it wrote. Reading a file (rather than wiring stack 00's outputs through
# terraform_remote_state) keeps the stacks loosely coupled. With EKS you would
# use the aws_eks_cluster data source plus an exec block calling
# `aws eks get-token` here instead.

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
