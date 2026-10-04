# 01 · GitOps and Argo CD: how it actually works

You know Terraform: you write desired state, run `plan`, run `apply`, and a
state file remembers what exists. Argo CD is the same idea with three
differences that change everything:

| | Terraform / OpenTofu | Argo CD |
|---|---|---|
| Who runs it | You or a CI job, when triggered | A controller inside the cluster, **all the time** |
| Source of desired state | `.tf` files on the machine running `apply` | A Git repo (or Helm/OCI repo) it pulls from |
| "State file" | `terraform.tfstate` | The live cluster itself (Kubernetes API) |
| Drift | Found on the next `plan`, if someone runs one | Found within minutes, optionally fixed automatically |
| Access | CI needs cloud/cluster credentials | Nothing outside the cluster needs cluster credentials |

That last row is the security argument for GitOps. In a push model, your CI
runner holds a kubeconfig that can change production. In the pull model, CI
only needs to write to Git. The cluster reaches out and pulls.

## The four GitOps principles (OpenGitOps, CNCF)

1. **Declarative**: the system is described as desired state, not as steps.
2. **Versioned and immutable**: that state lives in Git, so every change is a
   commit with an author, a review and a revert button.
3. **Pulled automatically**: an agent pulls the desired state; nobody pushes.
4. **Continuously reconciled**: the agent keeps comparing and correcting.

## Inside Argo CD

Argo CD is a handful of Deployments in the `argocd` namespace. Each has one job:

```
            Git repo / Helm repo
                    │  (1) clone, render
                    ▼
   ┌──────────────────────────────┐
   │ argocd-repo-server           │  Runs helm template / kustomize build /
   │                              │  plain YAML. Returns rendered manifests.
   └──────────────┬───────────────┘  Has NO cluster credentials.
                  │ (2) manifests
                  ▼
   ┌──────────────────────────────┐
   │ argocd-application-controller│  Compares rendered manifests with live
   │                              │  objects (the "diff"), sets Sync and
   │                              │  Health status, applies changes.
   └──────────────┬───────────────┘
                  │ (3) kubectl apply-equivalent
                  ▼
            Kubernetes API server

   argocd-server            UI + API + CLI endpoint, SSO, RBAC checks
   argocd-applicationset-controller   Generates Applications from templates
   argocd-redis             Cache for rendered manifests and live state
   argocd-dex-server        Optional SSO broker (disabled in this lab)
   argocd-notifications     Optional Slack/email/webhook alerts (disabled here)
```

The split matters for security: the component that runs untrusted tooling
(Helm, Kustomize, plugins) is the one without cluster write access.

## The objects you write

### Application

"Take *this* path in *this* repo at *this* revision, render it, and make
*that* namespace in *that* cluster match it." See
[`gitops/root/platform/openbao.yaml`](../gitops/root/platform/openbao.yaml).

Two statuses you will look at constantly:

- **Sync status**: does the cluster match Git? `Synced` or `OutOfSync`.
- **Health status**: is what's running working? `Healthy`, `Progressing`,
  `Degraded`, `Missing`. Argo CD knows how to judge Deployments, StatefulSets,
  PVCs and many CRDs (including ExternalSecret).

Synced but Degraded is common and useful: "Git was applied, but the pods are
crash-looping."

### syncPolicy: the knobs that matter in production

```yaml
syncPolicy:
  automated:
    prune: true      # delete live objects that were removed from Git
    selfHeal: true   # revert manual kubectl edits back to Git
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
  retry: { limit: 10, backoff: { duration: 15s, factor: 2, maxDuration: 3m } }
```

- Without `automated`, Argo CD only *reports* drift and waits for someone to
  press Sync. Some teams run prod this way. Most now auto-sync and gate changes
  at the pull-request level instead.
- `prune` is off by default because deleting things is dangerous. Turn it on
  deliberately.
- `selfHeal` is what makes "nobody runs kubectl in prod" enforceable.

### AppProject

A security boundary. It restricts which repos an Application may use, which
clusters/namespaces it may deploy to, and which resource kinds it may create.
This lab has three:

- `bootstrap`: the root app only; may create Applications and nothing else.
- `platform`: trusted operators (OpenBao, External Secrets, Argo CD itself).
- `apps`: product teams; only `demo-*` namespaces, only our repo, and **plain
  Secrets are forbidden** so secrets can only come from OpenBao.

### ApplicationSet

A template plus a generator that stamps out Applications. This lab uses the
Git directory generator: every folder under `gitops/apps/demo/overlays/`
becomes an Application. Other generators: `list`, `cluster` (one app per
registered cluster, the standard multi-cluster pattern), `matrix`, `pull
request` (preview environments per PR), `scm provider`.

### App of apps

One Application (`root`) whose source folder contains *other* Application
manifests. You bootstrap one object; it brings in everything else. That is how
the whole platform here comes up from a single `helm_release` in OpenTofu.

### Sync waves and hooks

Within a sync, resources are applied in order of the
`argocd.argoproj.io/sync-wave` annotation (lowest first), and Argo CD waits
for each wave to be healthy before starting the next. This lab uses:

| Wave | What |
|---|---|
| -2 | AppProjects |
| -1 | Argo CD (self-management) |
| 0 | OpenBao, External Secrets Operator |
| 2 | Demo ApplicationSet |

Hooks (`PreSync`, `PostSync`, `SyncFail`) run Jobs around a sync, for example
database migrations.

## Argo CD 3.x: what changed that you'll see in job interviews

- **3.0 (2025)**: annotation-based resource tracking by default (instead of a
  label, avoids clashes with other tools), fine-grained RBAC (update/delete of
  an app no longer implies rights on its resources), sensible default resource
  exclusions, legacy repo config removed.
- **3.1–3.3**: OCI registries as a first-class source, Source Hydrator (renders
  manifests and commits the *rendered* YAML to a branch so reviewers see the
  real diff), server-side diff improvements.
- **3.5 (mid-2026)**: mTLS between internal components, Git commit signature
  verification, ApplicationSets managed in the UI, impersonation and Source
  Hydrator promoted to beta.

## Argo CD vs Flux in one paragraph

Both are CNCF graduated and both do GitOps well. Argo CD has the UI, the
multi-team AppProject model and the larger share of jobs and surveys (roughly
half of GitOps users, versus low teens for Flux). Flux is a set of composable
controllers with no central UI, popular where everything is managed
programmatically. Learning Argo CD first is the safer career bet.

Next: [02 · OpenTofu for Terraform users](02-opentofu-for-terraform-users.md)
