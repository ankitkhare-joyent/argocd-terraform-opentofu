#!/usr/bin/env bash
# Thin wrapper: run OpenTofu in one stack with the lab environment loaded.
#   scripts/tofu.sh 10-bootstrap plan
set -euo pipefail
source "$(dirname "$0")/env.sh"
STACK="$1"; shift
cd "$LAB_ROOT/infra/stacks/$STACK"
tofu init -input=false >/dev/null
exec tofu "$@"
