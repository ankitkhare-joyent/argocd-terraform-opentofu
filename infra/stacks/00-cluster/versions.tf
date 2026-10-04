terraform {
  required_version = ">= 1.13.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
  }

  # OpenTofu-only feature: client-side state encryption.
  # The state file on disk is AES-GCM encrypted with a key derived from a
  # passphrase. Terraform has no equivalent; there you rely on the backend
  # (for example S3 server-side encryption) and anyone who can read the bucket
  # can read the state.
  #
  # Early variable evaluation (OpenTofu 1.8+) lets us use var.* here, so the
  # passphrase never lives in the code. In production you would swap pbkdf2 for
  # key_provider "aws_kms" or key_provider "openbao" (see stack 20).
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
