#!/usr/bin/env bash
# Frees the Docker VM's memory but keeps everything (cluster disk, OpenBao
# data, Git repo). `make start` brings it back; OpenBao unseals itself.
set -euo pipefail
docker stop platform-control-plane gitea 2>/dev/null || true
echo "Lab stopped. Memory released. Run 'make start' to resume."
