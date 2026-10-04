variable "app" {
  description = "Application name, e.g. demo."
  type        = string
}

variable "env" {
  description = "Environment name, e.g. dev or prod."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the app runs in."
  type        = string
}

variable "service_account" {
  description = "ServiceAccount (in var.namespace) allowed to log in for this app/env."
  type        = string
  default     = "openbao-reader"
}

variable "kv_mount" {
  type    = string
  default = "secret"
}

variable "kubernetes_auth_path" {
  type    = string
  default = "kubernetes"
}

variable "db_username" {
  type = string
}

variable "seed_version" {
  description = "Bump to generate and write a NEW password (rotation). The value itself is never in state."
  type        = number
  default     = 1
}
