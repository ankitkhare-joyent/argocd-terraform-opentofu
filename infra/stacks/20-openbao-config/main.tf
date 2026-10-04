# Layer 20: OpenBao's configuration, as code.
#
# OpenBao itself is deployed by Argo CD (gitops/platform/openbao). What lives
# *inside* OpenBao (mounts, auth methods, policies, roles) is managed here,
# because it is API configuration rather than Kubernetes objects. This split,
# Argo CD for workloads and OpenTofu for cloud/API config, is the common
# production pattern.

# KV version 2: versioned key/value secrets (keeps old versions, soft delete).
resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "Application secrets"
}

# --- Kubernetes auth: lets pods log in with their ServiceAccount token ------

resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  path        = "kubernetes"
  description = "Kubernetes ServiceAccount login for in-cluster workloads"
}

resource "vault_kubernetes_auth_backend_config" "this" {
  backend = vault_auth_backend.kubernetes.path
  # OpenBao runs inside the cluster, so it uses its own ServiceAccount token
  # and CA to call the TokenReview API. For an OpenBao outside the cluster you
  # would also set kubernetes_ca_cert and token_reviewer_jwt.
  kubernetes_host = "https://kubernetes.default.svc"
}

module "tenant" {
  source   = "../../modules/openbao-app-tenant"
  for_each = var.tenants

  app          = each.value.app
  env          = each.value.env
  namespace    = each.value.namespace
  db_username  = each.value.db_username
  seed_version = each.value.seed_version

  kv_mount             = vault_mount.kv.path
  kubernetes_auth_path = vault_auth_backend.kubernetes.path

  depends_on = [vault_kubernetes_auth_backend_config.this]
}

# --- GitHub Actions OIDC: how CI would run this stack in production ----------
# GitHub issues each workflow run a signed JWT. OpenBao verifies it against
# GitHub's public keys and checks the claims (repo, branch), so CI needs no
# stored OpenBao token at all.

resource "vault_jwt_auth_backend" "github" {
  count = var.github_repository == "" ? 0 : 1

  path               = "jwt-github"
  description        = "GitHub Actions OIDC"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  bound_issuer       = "https://token.actions.githubusercontent.com"
}

resource "vault_jwt_auth_backend_role" "tofu_ci" {
  count = var.github_repository == "" ? 0 : 1

  backend         = vault_jwt_auth_backend.github[0].path
  role_name       = "tofu-ci"
  role_type       = "jwt"
  user_claim      = "repository"
  bound_audiences = ["https://github.com/${split("/", var.github_repository)[0]}"]
  bound_claims = {
    repository = var.github_repository
    ref        = "refs/heads/main" # only main may apply; PR plans get a read-only role
  }
  token_policies = ["platform-admin"]
  token_ttl      = 900
}

# Pull requests only get to PLAN, with a read-only policy. A malicious PR that
# edits the workflow still cannot change OpenBao, because the "tofu-ci" role
# above only accepts tokens issued for refs/heads/main.
resource "vault_policy" "tofu_plan" {
  name   = "tofu-plan"
  policy = <<-EOT
    # Read the config this stack manages, to compute a diff.
    path "sys/mounts"            { capabilities = ["read"] }
    path "sys/mounts/*"          { capabilities = ["read"] }
    path "sys/auth"              { capabilities = ["read"] }
    path "sys/auth/*"            { capabilities = ["read"] }
    path "sys/policies/acl/*"    { capabilities = ["read", "list"] }
    path "auth/+/config"         { capabilities = ["read"] }
    path "auth/+/role/*"         { capabilities = ["read", "list"] }
    path "secret/metadata/*"     { capabilities = ["read", "list"] }
    # Decrypt and re-encrypt this stack's state (OpenTofu openbao key provider).
    path "transit/datakey/plaintext/tofu-state" { capabilities = ["update"] }
    path "transit/decrypt/tofu-state"           { capabilities = ["update"] }
  EOT
}

resource "vault_jwt_auth_backend_role" "tofu_ci_plan" {
  count = var.github_repository == "" ? 0 : 1

  backend           = vault_jwt_auth_backend.github[0].path
  role_name         = "tofu-ci-plan"
  role_type         = "jwt"
  user_claim        = "repository"
  bound_audiences   = ["https://github.com/${split("/", var.github_repository)[0]}"]
  bound_claims_type = "glob"
  bound_claims = {
    repository = var.github_repository
    event_name = "pull_request"
  }
  token_policies = [vault_policy.tofu_plan.name]
  token_ttl      = 900
}
