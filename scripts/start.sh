#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
docker start gitea platform-control-plane >/dev/null
echo "==> Waiting for the API server"
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
echo "==> Waiting for OpenBao to auto-unseal"
until curl -fsS "$BAO_ADDR/v1/sys/health" >/dev/null 2>&1; do sleep 3; done
"$(dirname "$0")/status.sh"
