#!/usr/bin/env bash
# Deletes everything this lab created: cluster, Gitea, local state and secrets.
# The source files (infra/, gitops/, docs/) and the local .git history stay.
set -euo pipefail
source "$(dirname "$0")/env.sh"

# Deleting the cluster removes everything inside it, so stacks 10 and 20 do
# not need their own destroy. In a real cloud account you WOULD destroy in
# reverse order (20 -> 10 -> 00) so nothing outside the cluster is orphaned.
"$(dirname "$0")/tofu.sh" 00-cluster destroy -auto-approve -input=false || kind delete cluster --name platform
docker rm -f gitea >/dev/null 2>&1 || true
docker volume rm lab-gitea-data lab-gitea-config >/dev/null 2>&1 || true
rm -rf "$LAB_ROOT/.state" "$LAB_ROOT/.kube" "$LAB_ROOT/.secrets"
git -C "$LAB_ROOT" remote remove gitea 2>/dev/null || true
git -C "$LAB_ROOT" config --unset-all http."$GITEA_URL/".extraHeader 2>/dev/null || true
echo "Lab removed."
