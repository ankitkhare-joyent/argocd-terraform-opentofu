# 08 · Day 2 operations

Installing is day 1. These are the things you do every week after that.

## Drift and self-heal

Someone runs `kubectl` in prod "just this once":

```bash
source scripts/env.sh
kubectl -n demo-prod scale deploy demo --replicas=5
kubectl -n demo-prod get deploy demo -w     # back to 2 within seconds
```

`selfHeal: true` reverted it. Git wins. To *see* drift without auto-fixing,
an app can run without `automated`; it then shows OutOfSync with a diff in
the UI (`argocd app diff demo-prod`).

When a field is *supposed* to differ (an HPA changing `replicas`, a webhook
injecting a `caBundle`), tell Argo CD with `ignoreDifferences` instead of
fighting the controller.

## Rollback

The GitOps way is `git revert`:

```bash
git log --oneline -3
git revert --no-edit HEAD
make push
```

`argocd app rollback demo-prod <history-id>` also exists, but it only works
with auto-sync off and the next sync puts Git's version back. Treat it as an
emergency brake, then fix Git.

## Secret rotation

Rotate the dev password in OpenBao (the way a human or a rotation job would):

```bash
bao kv patch secret/apps/demo/dev password="$(openssl rand -hex 12)"
```

Or the OpenTofu way: bump `seed_version` for `demo-dev` in stack 20's
`tenants` and run `make openbao-config` (write-only attributes are re-sent
only when their version changes).

Then watch it arrive:

```bash
kubectl -n demo-dev get externalsecret demo-db -w   # refreshes within 1m
kubectl -n demo-dev port-forward svc/demo 9898:80 &
curl -s localhost:9898/configs | jq                 # new value in the file, no restart
```

Mounted files update in place. **Environment variables don't**: the pod keeps
the value it started with. Options in production: read secrets from files,
restart on change with a controller like Stakater Reloader, or move to
dynamic database credentials where each pod gets its own short-lived user.

## Upgrades

Everything is a version bump in Git:

| Component | Where | Notes |
|---|---|---|
| Argo CD | `targetRevision` in `gitops/root/platform/argocd.yaml` | Read the upgrade notes between minor versions |
| OpenBao | `targetRevision` in `gitops/root/platform/openbao.yaml` | Snapshot Raft first; with 3 replicas, the StatefulSet rolls one at a time |
| External Secrets | `gitops/root/platform/external-secrets.yaml` | CRD API versions occasionally change between majors |
| Providers | `~>` constraints, then `tofu init -upgrade` | Commit the updated `.terraform.lock.hcl` |
| Kubernetes | `node_image` in stack 00 | kind needs a rebuild; EKS upgrades in place |

Automate the bump PRs with Renovate (it understands Helm `targetRevision`,
images, OpenTofu providers and `mise.toml`).

## Pause and resume (memory)

```bash
make stop    # docker stop the node and Gitea; frees ~2 GB
make start   # back in a minute or two
```

On start, watch OpenBao unseal itself: `kubectl -n openbao logs openbao-0 |
grep -i unseal`. With Shamir seals someone would have to type key shares now.

## Troubleshooting map

| Symptom | Where to look |
|---|---|
| App `Unknown` / ComparisonError | `argocd app get <app>`: usually a render error (bad YAML, missing chart version) or repo credentials |
| App OutOfSync forever | `argocd app diff <app>`: a controller mutating a field → `ignoreDifferences` |
| App Synced but Degraded | `kubectl describe` the unhealthy resource: image pull, PSA rejection, failing probes |
| `ExternalSecret` SecretSyncedError | `kubectl describe externalsecret`; then `kubectl -n external-secrets logs deploy/external-secrets`. Usually `permission denied` (role/policy/path) or the role doesn't exist yet (run stack 20) |
| SecretStore not Ready | OpenBao reachable? Kubernetes auth configured? Role bound to the right SA and namespace? |
| OpenBao pod not ready | `curl $BAO_ADDR/v1/sys/health`; `kubectl -n openbao logs openbao-0`; is the `openbao-seal` Secret present? |
| `tofu plan` in stack 20 fails on encryption | Your OpenBao token expired: `make bao-login && source scripts/env.sh` |
| `make up` stops at pre-flight | Docker VM is short on memory or CPU; stop other workloads |

Next: [09 · CI/CD with GitHub Actions](09-ci-cd-with-github-actions.md)
