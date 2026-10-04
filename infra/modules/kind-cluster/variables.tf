variable "name" {
  description = "Cluster name. kind prefixes the kubeconfig context with \"kind-\"."
  type        = string
}

variable "node_image" {
  description = "kindest/node image. Pin it (with a digest in real life) so every rebuild gets the same Kubernetes version."
  type        = string
}

variable "kubeconfig_path" {
  description = "Where kind writes the kubeconfig for this cluster."
  type        = string
}

variable "worker_count" {
  description = "Extra worker nodes. 0 keeps memory use low; the control-plane node also runs workloads."
  type        = number
  default     = 0

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 3
    error_message = "worker_count must be between 0 and 3 for a laptop lab."
  }
}

variable "port_mappings" {
  description = "NodePorts to expose on 127.0.0.1 of the host, keyed by a friendly name."
  type = map(object({
    node_port = number
    host_port = number
  }))
  default = {}
}
