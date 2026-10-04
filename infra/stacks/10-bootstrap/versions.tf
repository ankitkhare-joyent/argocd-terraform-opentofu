terraform {
  required_version = ">= 1.13.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  encryption {
    key_provider "pbkdf2" "local" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "local" {
      keys = key_provider.pbkdf2.local
    }
    state {
      method   = method.aes_gcm.local
      enforced = true
    }
    plan {
      method   = method.aes_gcm.local
      enforced = true
    }
  }
}
