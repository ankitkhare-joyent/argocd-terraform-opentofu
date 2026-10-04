terraform {
  required_version = ">= 1.13.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # This stack's state is encrypted with a key held by OpenBao itself, using
  # OpenTofu's "openbao" key provider and OpenBao's transit engine. The
  # transit key "tofu-state" was created by OpenBao's self-initialization.
  #
  # OpenTofu asks OpenBao to generate a data key, encrypts state locally with
  # it, and stores only the *wrapped* data key next to the state. Reading the
  # state later requires an OpenBao token allowed to use transit/tofu-state:
  # lose access to OpenBao, lose the ability to read this state.
  #
  # Address and token come from BAO_ADDR / BAO_TOKEN (scripts/bao-login.sh).
  encryption {
    key_provider "openbao" "transit" {
      transit_engine_path = "transit"
      key_name            = "tofu-state"
    }

    method "aes_gcm" "transit" {
      keys = key_provider.openbao.transit
    }

    state {
      method   = method.aes_gcm.transit
      enforced = true
    }

    plan {
      method   = method.aes_gcm.transit
      enforced = true
    }
  }
}
