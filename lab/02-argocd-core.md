# Lab 02 · Argo CD: render, compare, apply

One sitting, about 35 minutes. Background: [docs/01](../docs/01-gitops-and-argocd.md) and
[docs/05](../docs/05-step-2-bootstrap.md). Code: [gitops/root/](../gitops/root/),
[gitops/platform/argocd/values.yaml](../gitops/platform/argocd/values.yaml).

After this lab you can explain:

- which Argo CD component does what, and which one never touches the cluster
- the difference between *sync* status and *health* status
- what a render error looks like, and why it doesn't take your running app down

Answers to every **Predict** are at the bottom.

## Before you start

```bash
source lab/env.sh
apps
```

## 1. The components

**Predict (P1):** how many Argo CD pods are running? Which one is a StatefulSet, and why would that one be
special?

```bash
kubectl -n argocd get pods
kubectl -n argocd get statefulsets,deployments
```

## 2. What is root, exactly?

**Predict (P2):** `root` is the app of apps. Which repo path does it watch, which project is it in, and what kinds
of objects does it own?

```bash
argocd app get root -o json | jq '{source: .spec.source, project: .spec.project, rev: .status.sync.revision[0:7]}'
app_res root
```

Compare `rev` with `git ls-remote gitea main`. That's the commit Argo CD is running.

## 3. What the repo-server renders

The repo-server runs `kustomize build` / `helm template`. You can ask it for its output directly.

**Predict (P3):** for `demo-prod`, which kinds come out of the render, how many replicas, and which image tag?

```bash
argocd app manifests demo-prod --source git | grep -E "^kind:|image:|replicas"
```

Cross-check against Kustomize on your laptop: `kubectl kustomize gitops/apps/demo/overlays/prod | grep -E "image:|replicas"`.

## 4. How Argo CD knows what it owns

**Predict (P4):** Argo CD 3.x tracks resources with an annotation instead of a label. What does it contain for the
dev Deployment?

```bash
kubectl -n demo-dev get deploy demo -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{"\n"}'
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.timeout\.reconciliation}{"\n"}'
```

The second line is how often Argo CD polls Git.

## 5. Multiple sources

**Predict (P5):** the `openbao` app installs an upstream Helm chart but uses values from your repo. How many sources
does it have, and which one carries `ref: values`?

```bash
argocd app get openbao -o json | jq -c '[.spec.sources[] | {repoURL, chart, targetRevision, ref}]'
```

## Break it, then fix it: a commit that doesn't render

**Predict (P6):** you push invalid YAML into the dev overlay. Does Argo CD delete the dev pods? What do sync and
health say?

```bash
printf '\n  - this is: [not valid\n' >> gitops/apps/demo/overlays/dev/kustomization.yaml
git commit -qam "lab02: broken yaml" && make push
argocd app get demo-dev --refresh > /dev/null; sleep 5
argocd app get demo-dev -o json | jq -c '{sync: .status.sync.status, health: .status.health.status}'
argocd app get demo-dev -o json | jq -r '.status.conditions[0].message' | tail -c 200; echo
kubectl -n demo-dev get pods
```

Fix it the GitOps way, with a revert:

```bash
git revert --no-edit HEAD && make push
argocd app get demo-dev --refresh > /dev/null; wait_app demo-dev
```

## Check your predictions

**P1.** Five: `argocd-application-controller-0`, `argocd-applicationset-controller-…`, `argocd-redis-…`,
`argocd-repo-server-…`, `argocd-server-…` (Dex and notifications are disabled). The application controller is
the StatefulSet. With many clusters you run several replicas and shard clusters across them, and each shard needs a
stable identity.

**P2.**

```json
{ "source": { "repoURL": "http://gitea:3000/platform/platform.git", "path": "gitops/root",
              "targetRevision": "main", "directory": { "recurse": true } },
  "project": "bootstrap", "rev": "4e999a2" }
```

It owns only Argo CD objects: two AppProjects (`apps`, `platform`), three Applications (`argocd`,
`external-secrets`, `openbao`) and one ApplicationSet (`demo`), all Synced and the Applications Healthy. The
`bootstrap` project allows nothing else.

**P3.** `Service`, `ServiceAccount`, `Deployment` (`replicas: 2`, `image: ghcr.io/stefanprodan/podinfo:6.14.1`),
`ExternalSecret`, `SecretStore`. The same as your local `kubectl kustomize`, because it's the same tool on the same
commit.

**P4.** `demo-dev:apps/Deployment:demo-dev/demo`, which is `<app>:<group>/<kind>:<namespace>/<name>`. Polling is
`60s`. In production you'd add a Git webhook and keep polling as the fallback.

**P5.** Two:

```json
[{"repoURL":"https://openbao.github.io/openbao-helm","chart":"openbao","targetRevision":"0.30.2","ref":null},
 {"repoURL":"http://gitea:3000/platform/platform.git","chart":null,"targetRevision":"main","ref":"values"}]
```

The first source's `valueFiles` reads `$values/gitops/platform/openbao/values.yaml` from the second.

**P6.** Nothing is deleted. Sync becomes `Unknown` (Argo CD can't compute the desired state), health stays
`Healthy`, and the pod keeps running:

```
{"sync":"Unknown","health":"Healthy"}
... `kustomize build <path to cached source>/gitops/apps/demo/overlays/dev` failed exit status 1:
Error: invalid Kustomization: yaml: line 36: did not find expected ',' or ']'
```

Argo CD never applies a partial render, so a bad commit freezes the app at its last good state. After the revert
it's `Synced/Healthy` again within seconds.

## What to remember

- The repo-server renders and has no cluster credentials. The controller compares and applies.
- *Sync* answers "does the cluster match Git?" and *health* answers "is it working?". Read them separately.
- A commit that doesn't render is a `ComparisonError`, not an outage. Fix it in Git with `git revert`.
