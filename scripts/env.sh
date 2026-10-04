#!/usr/bin/env bash
# Source me:  source scripts/env.sh
# Sets up the environment every other script (and you, in a terminal) needs.
# Nothing here touches ~/.kube/config: this lab keeps its own kubeconfig.

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export LAB_ROOT

mkdir -p "$LAB_ROOT/.secrets" "$LAB_ROOT/.state" "$LAB_ROOT/.kube"
chmod 700 "$LAB_ROOT/.secrets"

# Cluster access (written by infra/stacks/00-cluster).
export KUBECONFIG="$LAB_ROOT/.kube/config"

# Passphrase for OpenTofu state encryption in stacks 00 and 10.
# Generated once; lose it and you can no longer read those state files.
if [[ ! -s "$LAB_ROOT/.secrets/state-passphrase" ]]; then
  openssl rand -base64 32 > "$LAB_ROOT/.secrets/state-passphrase"
  chmod 600 "$LAB_ROOT/.secrets/state-passphrase"
fi
export TF_VAR_state_passphrase="$(cat "$LAB_ROOT/.secrets/state-passphrase")"

# Endpoints exposed on localhost by kind / Docker.
export ARGOCD_URL="http://localhost:48080"
export GITEA_URL="http://localhost:43000"
export BAO_ADDR="http://localhost:48200"   # read by the bao CLI and OpenTofu's openbao key provider
export VAULT_ADDR="$BAO_ADDR"              # read by the Terraform/OpenTofu vault provider

# Tokens are filled in by scripts/bao-login.sh when OpenBao is up.
if [[ -s "$LAB_ROOT/.secrets/bao-token" ]]; then
  export BAO_TOKEN="$(cat "$LAB_ROOT/.secrets/bao-token")"
  export VAULT_TOKEN="$BAO_TOKEN"
fi
