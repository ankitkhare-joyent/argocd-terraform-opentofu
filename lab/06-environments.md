# Lab 06 · Environments: ApplicationSet, overlays, promotion

One sitting, about 45 minutes. Background: [docs/07](../docs/07-step-4-apps-and-promotion.md). Code:
[gitops/root/appsets/demo.yaml](../gitops/root/appsets/demo.yaml), [gitops/apps/demo/](../gitops/apps/demo/),
[infra/stacks/20-openbao-config/variables.tf](../infra/stacks/20-openbao-config/variables.tf).

After this lab you can explain:

- how a folder in Git becomes an Application, a namespace and running pods
- what Pod Security Admission `restricted` rejects
- what promotion is in GitOps, and the two halves of adding an environment (Git and OpenBao)

## Before you start

```bash
source lab/env.sh
apps
```

## 1. What the ApplicationSet generated

**Predict (P1):** two apps come from one template. What differs between them?

```bash
kubectl -n argocd get applications -l app.kubernetes.io/part-of=demo \
  -o custom-columns='APP:.metadata.name,ENV:.metadata.labels.env,DEST:.spec.destination.namespace,PATH:.spec.source.path'
kubectl get ns demo-dev -o json | jq -c '.metadata.labels | with_entries(select(.key|startswith("pod-security")))'
for e in dev prod; do printf '%-5s ' $e; kubectl -n demo-$e get deploy demo -o jsonpath='{.spec.template.spec.containers[0].image} replicas={.spec.replicas}{"\n"}'; done
```

## 2. Pod Security Admission

**Predict (P2):** you start a plain busybox pod in `demo-dev`. Accepted, accepted with a warning, or rejected?

```bash
kubectl -n demo-dev run psa-test --image=busybox:1.37 --restart=Never -- id
```

Then look at the `securityContext` in [deployment.yaml](../gitops/apps/demo/base/deployment.yaml): it answers every
complaint.

## 3. Promote dev's version to prod

**Predict (P3):** what is the whole promotion, in Git terms? How does prod roll out, and does it drop traffic?

```bash
sed -i '' 's/newTag: "6.14.1"/newTag: "6.15.0"/' gitops/apps/demo/overlays/prod/kustomization.yaml
git commit -qam "Promote demo 6.15.0 to prod" && make push
argocd app get demo-prod --refresh > /dev/null
until kubectl -n demo-prod get deploy demo -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -q 6.15.0; do sleep 2; done
kubectl -n demo-prod rollout status deploy/demo
argocd app get demo-prod -o json | jq -c '{sync: .status.sync.status, health: .status.health.status, rev: .status.sync.revision[0:7]}'
```

## Break it, then fix it: an environment with no secrets

Adding an environment has two halves: a folder for Argo CD, and a tenant in OpenBao. Do only the first.

**Predict (P4):** how long until `demo-staging` exists? Once it does, what breaks first?

```bash
cp -r gitops/apps/demo/overlays/dev gitops/apps/demo/overlays/staging
sed -i '' 's/dev/staging/g' gitops/apps/demo/overlays/staging/kustomization.yaml
git add gitops && git commit -qm "Add staging" && make push
kubectl -n argocd annotate applicationset demo argocd.argoproj.io/application-set-refresh=true --overwrite
until kubectl -n argocd get application demo-staging > /dev/null 2>&1; do sleep 3; done; sleep 30
argocd app get demo-staging -o json | jq -c '{sync: .status.sync.status, health: .status.health.status}'
app_res demo-staging
kubectl -n demo-staging get secretstore openbao -o json | jq -c '.status.conditions[0] | {reason, message}'
```

Now the second half. Add a `demo-staging` entry to `tenants` in
[variables.tf](../infra/stacks/20-openbao-config/variables.tf), next to `demo-dev`:

```hcl
    demo-staging = {
      app         = "demo"
      env         = "staging"
      namespace   = "demo-staging"
      db_username = "demo_staging_app"
    }
```

```bash
scripts/tofu.sh 20-openbao-config apply      # review: 3 to add (policy, role, seeded secret)
sleep 60; argocd app get demo-staging -o json | jq -c '{sync: .status.sync.status, health: .status.health.status, op: .status.operationState.message}'
```

**Predict (P5):** OpenBao now has the role. Does staging heal by itself?

```bash
argocd app terminate-op demo-staging 2>/dev/null; argocd app sync demo-staging > /dev/null
wait_app demo-staging; es_status demo-staging
```

Remove staging again (Git first, then OpenBao):

```bash
git rm -rq gitops/apps/demo/overlays/staging && git commit -qm "Remove staging" && make push
kubectl -n argocd annotate applicationset demo argocd.argoproj.io/application-set-refresh=true --overwrite
until ! kubectl -n argocd get application demo-staging > /dev/null 2>&1; do sleep 3; done; echo "app gone"
kubectl get ns demo-staging
```

**Predict (P6):** the app is gone. Is the namespace?

```bash
kubectl delete ns demo-staging
git checkout infra/stacks/20-openbao-config/variables.tf     # drop the tenant entry
scripts/tofu.sh 20-openbao-config apply                       # 3 to destroy
```

## Check your predictions

**P1.** Only the per-environment values: name `demo-dev`/`demo-prod`, label `env`, namespace and overlay path.
Both namespaces carry `pod-security.kubernetes.io/enforce: restricted` (with `enforce-version: latest`). Images
before promotion: dev `podinfo:6.15.0 replicas=1`, prod `podinfo:6.14.1 replicas=2`.

**P2.** Rejected:

```
Error from server (Forbidden): pods "psa-test" is forbidden: violates PodSecurity "restricted:latest":
allowPrivilegeEscalation != false ..., unrestricted capabilities ..., runAsNonRoot != true ...,
seccompProfile ...
```

**P3.** One line (`newTag`) in one file, committed and pushed. In a team that's a reviewed PR. Argo CD synced
it after the refresh and the Deployment did a rolling update: new pods become ready before old ones go, so there's no
downtime. Result: `{"sync":"Synced","health":"Healthy","rev":"<your commit>"}`. Note the `until` loop:
`rollout status` before Argo CD has applied the change only reports the *old* rollout as complete.

**P4.** About 6 seconds after the refresh annotation. Without it, up to 3 minutes, because the ApplicationSet
polls Git. The ServiceAccount and SecretStore sync (wave -2), but the store is `Degraded`:
`{"reason":"InvalidProviderConfig","message":"unable to create client"}`, and the ESO log shows the Kubernetes
login being refused, because OpenBao has no `demo-staging` role. The ExternalSecret, Deployment and Service stay
`Missing`: waves stop at the first unhealthy one, so no pod starts without its secret. The app is
`OutOfSync/Degraded`.

**P5.** No. OpenTofu printed `Apply complete! Resources: 3 added`, but five minutes later staging was still
`OutOfSync`. The last operation said `Operation terminated (retried 2 times)`, and **auto-sync doesn't retry a commit
whose sync already failed**. Git hadn't changed, so nothing triggered a new attempt. One manual
`argocd app sync demo-staging` and it was `Synced/Healthy` with `True  SecretSynced` 11 seconds later. Pushing any
new commit would also have done it.

**P6.** No. The app was deleted 9 seconds after the refresh, and its resources with it (`No resources found in
demo-staging namespace`), but the namespace stays `Active`. Argo CD created it through `CreateNamespace=true`, which
doesn't put the namespace under management. Delete it yourself. Then `apply` reports `3 destroyed`.

## What to remember

- An environment is a folder (Argo CD) plus a tenant (OpenBao). Do the OpenBao half first and nothing waits.
- Promotion is a reviewed Git change. The rollout itself is just Kubernetes.
- After fixing something *outside* Git (an OpenBao role), auto-sync won't retry on its own. Sync by hand.
