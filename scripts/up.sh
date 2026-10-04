#!/usr/bin/env bash
# Builds the whole lab from nothing. Safe to re-run: every step is idempotent.
set -euo pipefail
source "$(dirname "$0")/env.sh"
S="$LAB_ROOT/scripts"

# Pre-flight: the lab needs roughly 2.5 GB free in the Docker VM. kind's
# kubeadm init times out (not a clear error) when the VM is starved.
"$S/preflight.sh"

echo "==> [1/6] Cluster (OpenTofu stack 00)"
"$S/tofu.sh" 00-cluster apply -auto-approve -input=false

echo "==> [2/6] Git server + push this repo"
"$S/git-server.sh"

echo "==> [3/6] Bootstrap: OpenBao secret zero, Argo CD, root app (OpenTofu stack 10)"
TF_VAR_git_token="$(cat "$LAB_ROOT/.secrets/gitea-argocd-token")" \
  "$S/tofu.sh" 10-bootstrap apply -auto-approve -input=false

echo "==> [4/6] Argo CD is now installing OpenBao and External Secrets from Git"
"$S/bao-login.sh"
source "$S/env.sh"

echo "==> [5/6] OpenBao configuration (OpenTofu stack 20, state encrypted by OpenBao transit)"
"$S/tofu.sh" 20-openbao-config apply -auto-approve -input=false

echo "==> [6/6] Waiting for the demo apps to become Healthy"
for app in demo-dev demo-prod; do
  until kubectl -n argocd get application "$app" >/dev/null 2>&1; do sleep 5; done
  kubectl -n argocd wait application "$app" --for=jsonpath='{.status.health.status}'=Healthy --timeout=600s
done

"$S/status.sh"
