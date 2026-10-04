terraform {
  required_version = ">= 1.11.0"

  required_providers {
    vault = {
      # HashiCorp's Vault provider works unchanged against OpenBao because
      # OpenBao keeps the same HTTP API.
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
