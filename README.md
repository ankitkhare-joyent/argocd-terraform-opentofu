# Argo CD + OpenTofu + OpenBao: a production-shaped GitOps platform on your laptop

A learning lab that builds a small internal platform the way platform teams
build real ones, scaled down to run on one kind cluster:

- **OpenTofu** creates the cluster and bootstraps it, with encrypted state
  and no secrets stored in state.
- **Argo CD** deploys everything else from Git, including its own upgrades,
  using the app-of-apps pattern, AppProjects and an ApplicationSet.
- **OpenBao** (the open source Vault fork) holds every secret. It
  initializes and unseals itself, and apps get secrets through **External
  Secrets Operator** with per-namespace identities.
- A demo app runs in `dev` and `prod`; promotion is a one-line Git change.

## Start here

```bash
mise install    # pinned versions of tofu, kubectl, helm, kind, argocd, bao
make up         # ~5-8 minutes the first time; needs ~2.5 GB free in Docker
make status
```

Then read **[docs/00-start-here.md](docs/00-start-here.md)** and follow the
pages in order. The architecture diagram is the last page,
[docs/11-architecture.md](docs/11-architecture.md).

Then get hands-on with **[lab/](lab/README.md)**: seven drills, one component per sitting
(OpenTofu state, Argo CD, projects and waves, OpenBao, secret delivery, environments, day 2). Each one has you
predict, run, check, then break and fix, with answers recorded on a freshly reset stack.

```bash
make stop       # pause and free Docker memory, keep everything
make start      # resume
make down       # remove everything the lab created
make help       # all targets
```

## Versions (October 2026)

| Tool | Version |
|---|---|
| OpenTofu | 1.13.1 |
| Argo CD | 3.5.x (chart argo-cd 10.9.6) |
| OpenBao | 2.7.1 (chart openbao 0.30.2) |
| External Secrets Operator | 2.11.0 |
| Kubernetes (kind node) | 1.36.4 |
| Providers | helm 3.3, kubernetes 3.3, vault 5.12, random 3.9, tehcyx/kind 0.11 |

## About the Git URL in the manifests

Argo CD in this lab watches a local Gitea server, so the manifests use
`http://gitea:3000/platform/platform.git` (in `gitops/root/` and the bootstrap
variables). `make up` pushes this folder there through a second Git remote named
`gitea` (`origin` stays GitHub), and `make push` sends your commits to Gitea
for Argo CD to pick up. Push to GitHub with `git push origin` as usual.

To point Argo CD at this GitHub repo instead, replace that URL with the
GitHub HTTPS URL in `gitops/root/**/*.yaml` and in `git_repo_url` in
`infra/stacks/10-bootstrap/variables.tf`, and pass a GitHub fine-grained
token with read-only *Contents* access as `TF_VAR_git_token` (plus your
GitHub username as `git_username`).
