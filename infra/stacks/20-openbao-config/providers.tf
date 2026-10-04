# No credentials in code. The provider reads VAULT_ADDR and VAULT_TOKEN from
# the environment, exactly as a CI job would after logging in to OpenBao with
# its GitHub OIDC token (see .github/workflows/tofu.yml).
provider "vault" {
  # skip_child_token keeps things simple: use the login token directly
  # instead of minting a short-lived child token per run.
  skip_child_token = true
}
