#!/usr/bin/env bash
# Runs Gitea in Docker as a stand-in for GitHub/GitLab, creates the
# "platform" repo, and pushes this folder to it.
#
# Gitea joins the "kind" Docker network so pods (Argo CD) can reach it at
# http://gitea:3000, while you reach it at http://localhost:43000.
set -euo pipefail
source "$(dirname "$0")/env.sh"

IMAGE="gitea/gitea:28.0.0-rootless"
USER_NAME="platform"

if ! docker network inspect kind >/dev/null 2>&1; then
  echo "The kind Docker network does not exist yet. Create the cluster first (make cluster)." >&2
  exit 1
fi

if [[ -z "$(docker ps -aq -f name='^gitea$')" ]]; then
  echo "==> Starting Gitea"
  docker run -d --name gitea --network kind --restart unless-stopped \
    --memory 256m \
    -p 127.0.0.1:43000:3000 \
    -v lab-gitea-data:/var/lib/gitea -v lab-gitea-config:/etc/gitea \
    -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__server__ROOT_URL="$GITEA_URL/" \
    -e GITEA__service__DISABLE_REGISTRATION=true \
    -e GITEA__database__DB_TYPE=sqlite3 \
    "$IMAGE" >/dev/null
else
  docker start gitea >/dev/null
fi

echo "==> Waiting for Gitea"
until curl -fsS "$GITEA_URL/api/healthz" >/dev/null 2>&1; do sleep 2; done

if [[ ! -s "$LAB_ROOT/.secrets/gitea-password" ]]; then
  openssl rand -hex 16 > "$LAB_ROOT/.secrets/gitea-password"
  docker exec gitea gitea admin user create --admin \
    --username "$USER_NAME" --email platform@lab.local \
    --password "$(cat "$LAB_ROOT/.secrets/gitea-password")" \
    --must-change-password=false >/dev/null
fi
PASS="$(cat "$LAB_ROOT/.secrets/gitea-password")"

# Two tokens, two scopes. Argo CD only ever needs to READ the repo.
if [[ ! -s "$LAB_ROOT/.secrets/gitea-argocd-token" ]]; then
  docker exec gitea gitea admin user generate-access-token --username "$USER_NAME" \
    --token-name argocd-read --scopes read:repository --raw > "$LAB_ROOT/.secrets/gitea-argocd-token"
fi
if [[ ! -s "$LAB_ROOT/.secrets/gitea-push-token" ]]; then
  docker exec gitea gitea admin user generate-access-token --username "$USER_NAME" \
    --token-name local-push --scopes write:repository --raw > "$LAB_ROOT/.secrets/gitea-push-token"
fi

if ! curl -fsS -u "$USER_NAME:$PASS" "$GITEA_URL/api/v1/repos/$USER_NAME/platform" >/dev/null 2>&1; then
  echo "==> Creating private repo $USER_NAME/platform"
  curl -fsS -u "$USER_NAME:$PASS" -H 'Content-Type: application/json' \
    -d '{"name":"platform","private":true,"default_branch":"main"}' \
    "$GITEA_URL/api/v1/user/repos" >/dev/null
fi

# This lab folder is the Git repo Argo CD watches.
cd "$LAB_ROOT"
if [[ ! -d .git ]]; then
  git init -q -b main
  git add -A
  git commit -q -m "Initial platform repo: OpenTofu stacks and GitOps manifests"
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "$GITEA_URL/$USER_NAME/platform.git"
# Token goes in a repo-local header, not in the remote URL.
git config http."$GITEA_URL/".extraHeader "Authorization: token $(cat .secrets/gitea-push-token)"
git push -q -u origin main
echo "==> Pushed to $GITEA_URL/$USER_NAME/platform"
