#!/usr/bin/env bash
# Checks the Docker VM has room for the lab before starting it. When the VM
# is starved, kind's kubeadm init just times out with a long stack trace, so
# it is worth checking first.
set -euo pipefail
NEED_MB="${LAB_NEED_MB:-2500}"

# Ask the VM itself (a tiny container sees the VM's /proc), not the host Mac.
read -r avail_mb < <(docker run --rm --network none busybox:1.37 free -m | awk '/^Mem:/ {print $7}')
read -r load1 _ < <(docker run --rm --network none busybox:1.37 cat /proc/loadavg)
ncpu=$(docker info --format '{{.NCPU}}')

echo "Docker VM: ~${avail_mb} MB memory available (lab needs ~${NEED_MB} MB), load ${load1} on ${ncpu} CPUs."

if (( avail_mb < NEED_MB )); then
  echo "Not enough memory. Stop other Docker workloads or raise Docker Desktop's memory limit, then retry." >&2
  exit 1
fi
if awk -v l="$load1" -v c="$ncpu" 'BEGIN { exit !(l > 3 * c) }'; then
  echo "The Docker VM is CPU-saturated (load > 3x CPUs). Cluster start-up will likely time out." >&2
  echo "Wait for other workloads to settle, or set LAB_SKIP_LOAD_CHECK=1 to try anyway." >&2
  [[ "${LAB_SKIP_LOAD_CHECK:-0}" == "1" ]] || exit 1
fi
