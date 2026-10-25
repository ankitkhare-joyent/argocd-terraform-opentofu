# Source this once per terminal, from the repo root, after `make up`:
#
#   source lab/env.sh
#
# It loads the lab environment (kubeconfig, endpoints, OpenTofu passphrase),
# puts the pinned CLIs from mise.toml on PATH, logs the argocd CLI in, and
# defines a few helpers. Nothing here prints a secret value.

source scripts/env.sh
export PATH="$(mise bin-paths 2>/dev/null | tr '\n' ':')$PATH"

if ! kubectl get --raw /readyz >/dev/null 2>&1; then
  echo "lab/env.sh: cluster not reachable. Run 'make up' (or 'make start' after 'make stop')." >&2
else
  argocd login localhost:48080 --plaintext --username admin \
    --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" \
    >/dev/null 2>&1 || echo "lab/env.sh: argocd login failed (is the argocd app Healthy?)" >&2
  [ -n "${BAO_TOKEN:-}" ] || echo "lab/env.sh: no OpenBao token yet. Run 'make bao-login', then source this again." >&2
fi

# apps                      -> every Argo CD Application: sync, health, last operation
apps() {
  kubectl -n argocd get applications -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,OP:.status.operationState.phase'
}

# app_res demo-dev          -> the resources of one app, with per-resource sync/health
app_res() {
  argocd app get "$1" -o json \
    | jq -r '.status.resources[] | [.kind, .name, .status, (.health.status // "-")] | @tsv' | column -t
}

# wait_app demo-dev Synced Healthy   -> block until an app reaches that state (max 5 min)
wait_app() {
  local app=$1 sync=${2:-Synced} health=${3:-Healthy} i
  for i in $(seq 1 100); do
    [ "$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" = "$sync/$health" ] \
      && { echo "$app: $sync/$health"; return 0; }
    sleep 3
  done
  echo "$app: still $(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}')" >&2
  return 1
}

# es_status demo-dev        -> the ExternalSecret's Ready condition, in one line
es_status() {
  kubectl -n "$1" get externalsecret demo-db -o json \
    | jq -r '.status.conditions[]? | select(.type=="Ready") | "\(.status)  \(.reason)  \(.message)"'
}

# bao_keys apps/demo/dev    -> a KV secret's field names and version, never the values
bao_keys() {
  bao kv get -format=json "secret/$1" 2>&1 | jq -c '{fields: (.data.data | keys), version: .data.metadata.version}' 2>/dev/null \
    || bao kv get "secret/$1" 2>&1 | tail -2
}

# fp VALUE                  -> a short fingerprint, so you can compare secrets without printing them
fp() { printf '%s' "$1" | shasum -a 256 | cut -c1-12; }
