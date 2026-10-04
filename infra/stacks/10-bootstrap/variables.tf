variable "state_passphrase" {
  type      = string
  sensitive = true
}

variable "kubeconfig_path" {
  type    = string
  default = "../../../.kube/config"
}

variable "kube_context" {
  type    = string
  default = "kind-platform"
}

variable "git_repo_url" {
  description = "The platform repo as seen from inside the cluster (the Gitea container on the kind Docker network)."
  type        = string
  default     = "http://gitea:3000/platform/platform.git"
}

variable "git_username" {
  type    = string
  default = "platform"
}

variable "git_token" {
  description = "Read-only Gitea token for Argo CD. Ephemeral: it passes through OpenTofu without landing in state."
  type        = string
  ephemeral   = true
}
