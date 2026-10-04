#!/usr/bin/env bash
# Logs in to OpenBao as tofu-admin (created by OpenBao's self-initialization)
# and saves a 1-hour token to .secrets/bao-token for OpenTofu stack 20.
#
# In CI this step is replaced by a GitHub OIDC login, see
# .github/workflows/tofu.yml.
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "==> Waiting for OpenBao to be initialized and unsealed"
until curl -fsS "$BAO_ADDR/v1/sys/health" >/dev/null 2>&1; do sleep 3; done

PASS="$(kubectl -n openbao get secret openbao-bootstrap-admin -o jsonpath='{.data.INITIAL_ADMIN_PASSWORD}' | base64 -d)"
bao login -token-only -method=userpass username=tofu-admin password="$PASS" > "$LAB_ROOT/.secrets/bao-token"
chmod 600 "$LAB_ROOT/.secrets/bao-token"
echo "==> Token saved. Run: source scripts/env.sh"
