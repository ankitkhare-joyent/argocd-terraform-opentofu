variable "namespace" {
  type    = string
  default = "argocd"
}

variable "chart_version" {
  description = "argo-helm 'argo-cd' chart version. Must match gitops/root/platform/argocd.yaml so Argo CD adopts the same release it was bootstrapped with."
  type        = string
}

variable "values_yaml" {
  description = "Contents of gitops/platform/argocd/values.yaml. Shared with the self-managed Application, so OpenTofu and Argo CD agree on the config."
  type        = string
}

variable "repo_url" {
  description = "Git URL Argo CD reads from, as seen from inside the cluster."
  type        = string
}

variable "repo_username" {
  type = string
}

variable "repo_password" {
  description = "Git token. Ephemeral: used to write the Kubernetes Secret, never stored in OpenTofu state."
  type        = string
  ephemeral   = true
}

variable "repo_credentials_revision" {
  description = "Bump this number to push a rotated repo_password into the cluster. Write-only values cannot be diffed, so OpenTofu needs this hint."
  type        = number
  default     = 1
}

variable "target_revision" {
  description = "Branch (or tag) the root Application tracks."
  type        = string
  default     = "main"
}

variable "root_path" {
  description = "Path inside the repo that holds the app-of-apps."
  type        = string
  default     = "gitops/root"
}
