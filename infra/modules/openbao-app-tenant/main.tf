# "Tenant onboarding" for one app in one environment.
#
# Gives the app exactly one place to read secrets from and exactly one
# identity that may read it:
#
#   ServiceAccount <namespace>/<service_account>
#       --(kubernetes auth role)-->  policy <app>-<env>-read
#       --(allows read on)------->  secret/apps/<app>/<env>
#
# Platform teams usually call this module once per app/env from a list, so
# onboarding a new service is a 5-line pull request.

locals {
  name        = "${var.app}-${var.env}"
  secret_path = "apps/${var.app}/${var.env}"
}

resource "vault_policy" "read" {
  name   = "${local.name}-read"
  policy = <<-EOT
    # KV v2 stores data under <mount>/data/ and version info under <mount>/metadata/.
    path "${var.kv_mount}/data/${local.secret_path}" {
      capabilities = ["read"]
    }
    path "${var.kv_mount}/metadata/${local.secret_path}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "this" {
  backend                          = var.kubernetes_auth_path
  role_name                        = local.name
  bound_service_account_names      = [var.service_account]
  bound_service_account_namespaces = [var.namespace]
  token_policies                   = [vault_policy.read.name]
  token_ttl                        = 900  # 15 minutes
  token_max_ttl                    = 3600 # ESO simply logs in again
}

# Generated for this run only; never stored in state.
ephemeral "random_password" "db" {
  length  = 24
  special = false
}

resource "vault_kv_secret_v2" "seed" {
  mount = var.kv_mount
  name  = local.secret_path

  # Write-only (OpenTofu 1.11+, vault provider 5.x): sent to OpenBao, not
  # recorded in state. OpenBao stays the only source of truth for the value.
  data_json_wo = jsonencode({
    username = var.db_username
    password = ephemeral.random_password.db.result
  })
  data_json_wo_version = var.seed_version
}
