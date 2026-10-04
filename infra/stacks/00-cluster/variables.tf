variable "state_passphrase" {
  description = "Passphrase for state encryption. Supplied via TF_VAR_state_passphrase by scripts/env.sh."
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  type    = string
  default = "platform"
}

variable "node_image" {
  description = "One minor version behind the newest kind image, the way managed services like EKS usually lag upstream."
  type        = string
  default     = "kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
}
