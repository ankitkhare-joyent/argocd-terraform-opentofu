# 05 · Step 2: Git and the Argo CD bootstrap (stack 10)

**Goal:** give the cluster a Git repo to follow, install Argo CD with
OpenTofu, and watch Argo CD take over from there.

**Files:** [`scripts/git-server.sh`](../scripts/git-server.sh),
[`infra/stacks/10-bootstrap/`](../infra/stacks/10-bootstrap/),
[`infra/modules/argocd-bootstrap/`](../infra/modules/argocd-bootstrap/),
[`gitops/root/`](../gitops/root/)

## Part A: the Git server

```bash
make git
```

Gitea runs as a Docker container on the same Docker network as the kind
node. You use it at http://localhost:43000; pods reach it at
`http://gitea:3000`. It plays the role GitHub plays at work.

The script creates a user `platform`, a **private** repo
`platform/platform`, and two tokens with different scopes:

| Token | Scope | Used by |
|---|---|---|
| `.secrets/gitea-argocd-token` | `read:repository` | Argo CD (it never needs to write) |
| `.secrets/gitea-push-token` | `write:repository` | You, for `git push` |

Then it turns this folder into a Git repo and pushes it. From now on, **this
folder is the source of truth**: edit, commit, `make push`, and Argo CD
follows.

## Part B: the bootstrap

```bash
make bootstrap
```

### Read [`10-bootstrap/main.tf`](../infra/stacks/10-bootstrap/main.tf)

Two halves:

**Secret zero for OpenBao.** Two Kubernetes Secrets in the `openbao`
namespace: the seal key and the first admin password. Look at how they are
made:

```hcl
ephemeral "random_bytes" "openbao_seal_key" { length = 32 }

resource "kubernetes_secret_v1" "openbao_seal" {
  data_wo          = { BAO_STATIC_UNSEAL_KEY = ephemeral.random_bytes.openbao_seal_key.base64 }
  data_wo_revision = 1
}
```

The value is generated, sent to Kubernetes, and forgotten. Check:

```bash
cd infra/stacks/10-bootstrap
tofu show -json | grep -c BAO_STATIC_UNSEAL_KEY   # 0: not in state
```

**Argo CD and the hand-off.** The module installs the `argo-cd` Helm chart,
a repository Secret (Argo CD finds repo credentials by the label
`argocd.argoproj.io/secret-type: repository`), and one Application named
`root`.

Two details worth noticing:

- The chart version is **read from Git**:
  `yamldecode(file(".../gitops/root/platform/argocd.yaml")).spec.sources[0].targetRevision`.
  The values file is the same file Argo CD uses. Bootstrap and GitOps can't
  drift apart.
- `lifecycle { ignore_changes = [values, version] }` on the Helm release:
  after bootstrap, Argo CD owns Argo CD. OpenTofu shouldn't fight it.

### Read [`gitops/root/`](../gitops/root/), the app of apps

`root` points at this folder with `directory.recurse: true`, so every YAML
file under it becomes a live object:

```
gitops/root/
├── projects/      wave -2   AppProjects: platform, apps
├── platform/      wave -1   argocd (Argo CD managing itself)
│                  wave  0   openbao, external-secrets
└── appsets/       wave  2   demo ApplicationSet → demo-dev, demo-prod
```

Each platform Application uses **multiple sources**: the chart from the
upstream Helm repo, plus `ref: values` pointing at our repo so
`$values/gitops/platform/<name>/values.yaml` can be used. Charts stay
upstream; config stays in Git.

## See it

Open http://localhost:48080 (user `admin`, password from
`make argocd-password`). Click `root` and watch the tree fill in.

```bash
source scripts/env.sh
kubectl -n argocd get applications
argocd login localhost:48080 --plaintext --username admin \
  --password "$(make -s argocd-password)"
argocd app get root
argocd app tree root 2>/dev/null || argocd app resources root
```

## Things to try

1. **Self-management.** In
   [`gitops/platform/argocd/values.yaml`](../gitops/platform/argocd/values.yaml)
   change `timeout.reconciliation: 60s` to `90s`. Commit and `make push`.
   Within a minute the `argocd` app goes OutOfSync → Synced and
   `kubectl -n argocd get cm argocd-cm -o yaml | grep reconciliation` shows
   the new value. You changed Argo CD's config without running Helm.
2. **Project guardrails.** Add a file `gitops/root/platform/oops.yaml` with an
   Application in project `apps` that targets namespace `kube-system`. Push.
   The app shows an error: the `apps` project doesn't allow that
   destination. Delete the file and push again.
3. **Why the root app has its own project.** Read the `bootstrap` project in
   [`modules/argocd-bootstrap/main.tf`](../infra/modules/argocd-bootstrap/main.tf):
   it may create Applications and AppProjects in `argocd` and nothing else.
   Even a compromised root app can't deploy a workload directly.

Next: [06 · Step 3, OpenBao and secrets](06-step-3-openbao-and-secrets.md)
