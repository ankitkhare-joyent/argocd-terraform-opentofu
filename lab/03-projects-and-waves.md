# Lab 03 · AppProjects, the app of apps, and sync waves

One sitting, about 30 minutes. Background: [docs/01](../docs/01-gitops-and-argocd.md) (AppProject, waves) and
[docs/05](../docs/05-step-2-bootstrap.md). Code: [gitops/root/projects/](../gitops/root/projects/),
[the bootstrap project](../infra/modules/argocd-bootstrap/main.tf), and the Application health check in
[gitops/platform/argocd/values.yaml](../gitops/platform/argocd/values.yaml).

After this lab you can explain:

- what each of the three AppProjects allows, and how to prove it
- why the root app waits for OpenBao before it creates the demo apps
- what to do when a sync is stuck waiting on something that will never become healthy

## Before you start

```bash
source lab/env.sh
apps
```

## 1. Three projects, three trust levels

**Predict (P1):** the `apps` project is for product teams. Which destinations does it allow, which cluster-scoped
kinds, and which namespaced kinds does it forbid?

```bash
for p in bootstrap platform apps; do
  echo "== $p"
  kubectl -n argocd get appproject $p -o json | jq -c '.spec | {destinations: [.destinations[].namespace],
    clusterAllow: .clusterResourceWhitelist, nsDeny: .namespaceResourceBlacklist, nsAllow: .namespaceResourceWhitelist}'
done
```

## 2. Sync waves

**Predict (P2):** in what order did `root` create its children? Put these in order: `apps` project, `openbao`,
`argocd`, the `demo` ApplicationSet.

```bash
grep -rn "sync-wave" gitops/root/
```

## 3. Why the waves actually wait

Since Argo CD 1.8, an Application's health is *not* passed up to the app that created it. Without a fix, `root`
would create the demo apps at the same moment as OpenBao, and they'd fail.

**Predict (P3):** what does `root` report as the health of its child Applications?

```bash
argocd app get root -o json | jq -c '.status.resources[] | {kind, name, health: .health.status}'
kubectl -n argocd get cm argocd-cm -o json | jq -r '.data | keys[] | select(startswith("resource.customizations.health"))'
```

## Break it, then fix it: an Application outside its project

You'll add an Application in the `apps` project that targets `kube-system`.

**Predict (P4):** does Argo CD create the Application object? Does anything get deployed into `kube-system`?

```bash
cat > gitops/root/platform/oops.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oops
  namespace: argocd
spec:
  project: apps
  source:
    repoURL: http://gitea:3000/platform/platform.git
    targetRevision: main
    path: gitops/apps/demo/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
EOF
git add gitops/root/platform/oops.yaml && git commit -qm "lab03: app outside its project" && make push
argocd app get root --refresh > /dev/null; sleep 12
argocd app get oops -o json | jq -c '{sync: .status.sync.status, health: .status.health.status, conditions: [.status.conditions[]? | .message]}'
kubectl -n kube-system get deploy demo 2>&1 | tail -1
```

Now remove it:

```bash
git revert --no-edit HEAD && make push
argocd app get root --refresh > /dev/null; sleep 20
apps
```

**Predict (P5):** after the revert, is `oops` gone and `root` Synced? If not, why not?

```bash
argocd app get root -o json | jq -c '{op: .status.operationState.phase, msg: .status.operationState.message}'
```

If `root` is stuck, unstick it and let auto-sync prune `oops`:

```bash
argocd app terminate-op root
sleep 15; apps
```

## Check your predictions

**P1.**

```
bootstrap  destinations [argocd]; clusterAllow []; nsAllow Application, ApplicationSet, AppProject
platform   destinations [argocd, openbao, external-secrets]; clusterAllow [{"group":"*","kind":"*"}]
apps       destinations [demo-*]; clusterAllow [Namespace]; nsDeny Secret, ResourceQuota, LimitRange
```

`apps` can't create a plain Secret at all, so secrets can only arrive through External Secrets.

**P2.** `-2` AppProjects (`apps`, `platform`), `-1` `argocd`, `0` `openbao` and `external-secrets`, `2` the
`demo` ApplicationSet. Inside each demo app there are waves too: ServiceAccount and SecretStore `-2`,
ExternalSecret `-1`, Deployment and Service `0`.

**P3.** `Healthy` for `argocd`, `external-secrets` and `openbao`, and the ApplicationSet says "All applications
have been generated successfully". The AppProjects report no health, because they have none. The custom check
`resource.customizations.health.argoproj.io_Application` is what makes Applications report health to `root`, so wave
2 waits for wave 0 to be Healthy.

**P4.** The Application object is created (`root` is allowed to create Applications), but it never deploys:

```
{"sync":"Unknown","health":"Unknown","conditions":["application destination server 'https://kubernetes.default.svc'
 and namespace 'kube-system' do not match any of the allowed destinations in project 'apps'"]}
```

and `kubectl -n kube-system get deploy demo` says `NotFound`.

**P5.** Not by itself. When I ran it, `oops` was still there and `root` was `OutOfSync` with:

```
{"op":"Running","msg":"waiting for healthy state of argoproj.io/Application/oops"}
```

The sync that *created* `oops` is still running, waiting for it to become healthy, which it never will. A running
operation blocks new ones, so the revert can't be applied. `argocd app terminate-op root` ends it, and auto-sync
then applies the new commit and prunes `oops`. All six apps were Synced / Healthy 15 seconds later. This is the
price of making waves wait: an unhealthy child holds the parent's sync open.

## What to remember

- AppProjects are where you say *no*: destinations, source repos and resource kinds.
- Sync waves only wait for what reports health. For child Applications that takes the custom health check.
- "Waiting for healthy state of …" on something that will never be healthy means `argocd app terminate-op`, then
  let the fixed commit sync.
