#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/env.sh"
echo
kubectl -n argocd get applications -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision' 2>/dev/null \
  || echo "Cluster not reachable (stopped or not created)."
echo
echo "Argo CD   $ARGOCD_URL   user: admin  password: make argocd-password"
echo "OpenBao   $BAO_ADDR/ui  user: tofu-admin (userpass)  password: make bao-password"
echo "Gitea     $GITEA_URL    user: platform  password: cat .secrets/gitea-password"
