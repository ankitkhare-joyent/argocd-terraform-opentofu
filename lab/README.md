# Hands-on lab: the platform, one component per sitting

The pages in [docs/](../docs) explain the design. This track has you poke each running component until you could
debug it on your own. It follows the boot order: OpenTofu first (it builds everything), then Argo CD, the
app-of-apps guardrails, OpenBao, the secret delivery path, the environments, and finally day-2 operations.

## Fresh start (do this first)

```bash
cd ~/workstuff/argocd-terraform-opentofu/argocd-terraform-opentofu
docker ps --format '{{.Names}}'     # nothing from another lab running? (the shared ec2-lakehouse-* is fine)
make down                           # wipe any previous lab: cluster, Gitea, state, secrets
make up                             # ~5 minutes; ends with six apps Synced / Healthy
source lab/env.sh                   # once per terminal: PATH, kubeconfig, argocd login, helpers
apps                                # sanity check: the six apps
```

Between sittings, `make stop` frees Docker's memory and `make start` brings everything back (OpenBao unseals
itself). After `make start`, run `make bao-login` and `source lab/env.sh` again, because the OpenBao token
lasts one hour.

## Every lab has the same shape

1. **Look**: real commands against your running stack.
2. **Predict** before you run: each step asks a question (P1, P2, …). Write your guess down first. The answers,
   with the output recorded on a freshly reset stack, are at the bottom of each file.
3. **Break it, then fix it**: at least one failure on purpose, so you've seen it before it happens for real.

The break-and-fix steps push commits to the lab's local Gitea. Each one tells you how to put Git back. If you get
lost, `git push -f gitea origin/main:main` restores Gitea to what's on GitHub, and Argo CD follows within a minute.

| Lab | Component | You'll be able to explain | Changes anything? |
|---|---|---|---|
| [01](01-opentofu-state.md) | OpenTofu stacks and state | what's in an encrypted state file; why secrets never land in it; what a wrong key looks like | no (plan only) |
| [02](02-argocd-core.md) | Argo CD | repo-server vs controller; sync vs health; what a render error looks like | pushes a broken commit, then reverts it |
| [03](03-projects-and-waves.md) | AppProjects, app of apps, waves | how a project blocks a bad Application; why a stuck sync needs `terminate-op` | pushes and removes a bad app |
| [04](04-openbao.md) | OpenBao | seal type, self-init, policies, Raft; auto-unseal after a pod dies | deletes the OpenBao pod |
| [05](05-secret-delivery.md) | Kubernetes auth + External Secrets | every hop from OpenBao to a file in the pod; why dev can't read prod | points dev at prod's path, then fixes it |
| [06](06-environments.md) | ApplicationSet, overlays, promotion | how an environment appears and disappears; PSA; promoting dev → prod | adds and removes a staging env (Git + OpenTofu) |
| [07](07-day-2.md) | Day 2 | self-heal and what it ignores; rotation reaching a pod; rollback by `git revert` | rotates the dev password |

Each lab is one sitting of 30-45 minutes. Do them in order: later labs reuse what you saw earlier.

## Helpers (from `source lab/env.sh`)

| Helper | What it does |
|---|---|
| `apps` | every Argo CD Application: sync, health, last operation |
| `app_res APP` | an app's resources with per-resource sync and health |
| `wait_app APP [SYNC] [HEALTH]` | block until an app reaches that state (default Synced Healthy, max 5 min) |
| `es_status NAMESPACE` | the `demo-db` ExternalSecret's Ready condition in one line |
| `bao_keys PATH` | a KV secret's field names and version, never the values (`bao_keys apps/demo/dev`) |
| `fp VALUE` | a 12-character fingerprint, so you can compare secrets without printing them |

Also on PATH: the pinned `tofu`, `kubectl`, `argocd`, `bao`, `helm`, `kind` from [mise.toml](../mise.toml).
`scripts/tofu.sh STACK ARGS` runs OpenTofu in one stack with the lab environment loaded.

None of the labs print a secret value. When a lab needs to compare two secrets, it compares fingerprints.

## If something is off

- `lab/env.sh: cluster not reachable`: the lab is stopped or gone. Run `make start` or `make up`.
- `bao` says `permission denied` on everything: your token expired. `make bao-login && source lab/env.sh`.
- An app stays `OutOfSync` after you fixed Git: its last sync failed on the old commit and auto-sync won't retry
  that commit. `argocd app terminate-op APP`, then `argocd app sync APP` (Lab 03 and 05 show why).
- A new overlay folder doesn't become an app: the ApplicationSet polls Git every 3 minutes.
  `kubectl -n argocd annotate applicationset demo argocd.argoproj.io/application-set-refresh=true --overwrite`.
- Numbers don't match the answers exactly: pod names, commit IDs, timings and token TTLs change every run. The
  shape and the reasoning should match.

## The platform, with the lab that covers each part

```
   you ── git push ──▶ Gitea ◀── pull ── 02 Argo CD (repo-server, controller)
    │                                         │ syncs, in waves (03)
    │ make up                                 ▼
    ▼                    ┌────────────────────┬─────────────────────┬───────────────────────┐
 01 OpenTofu ───────────▶│ 04 OpenBao          │ external-secrets    │ 06 demo-dev, demo-prod │
   00 cluster            │  seal, self-init,   │ 05 logs in with the │  (ApplicationSet,      │
   10 bootstrap ─secret──▶│  KV, k8s auth,      │◀── SA token, reads ─│   overlays, PSA)       │
      zero                │  transit            │    and writes the   │  07 drift, rotation,   │
   20 openbao-config ────▶│                     │    Secret ─────────▶│     rollback           │
                         └────────────────────┴─────────────────────┴───────────────────────┘
```
