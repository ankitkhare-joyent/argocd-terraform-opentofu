variable "tenants" {
  description = "Apps and environments to onboard. One entry = one policy, one Kubernetes auth role, one secret path."
  type = map(object({
    app         = string
    env         = string
    namespace   = string
    db_username = string
    # Bump to rotate the generated password.
    seed_version = optional(number, 1)
  }))
  default = {
    demo-dev = {
      app         = "demo"
      env         = "dev"
      namespace   = "demo-dev"
      db_username = "demo_dev_app"
    }
    demo-prod = {
      app         = "demo"
      env         = "prod"
      namespace   = "demo-prod"
      db_username = "demo_prod_app"
    }
  }
}

variable "github_repository" {
  description = "owner/repo allowed to run OpenTofu against OpenBao from GitHub Actions via OIDC. Empty disables the JWT auth method."
  type        = string
  default     = ""
}
