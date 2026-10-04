# 07 · Step 4: apps, environments and promotion

**Goal:** understand how one ApplicationSet and a Kustomize base with
overlays give you dev and prod, and promote a change from one to the other.

**Files:** [`gitops/root/appsets/demo.yaml`](../gitops/root/appsets/demo.yaml),
[`gitops/apps/demo/`](../gitops/apps/demo/)

## The layout

```
gitops/apps/demo/
├── base/                     what every environment shares
│   ├── deployment.yaml       podinfo, hardened securityContext, probes, limits
│   ├── service.yaml
│   ├── serviceaccount.yaml   identity used only to log in to OpenBao
│   ├── secretstore.yaml      this namespace's connection to OpenBao
│   └── externalsecret.yaml   "I need secret apps/demo/<env>"
└── overlays/
    ├── dev/kustomization.yaml    image 6.15.0, 1 replica, role demo-dev
    └── prod/kustomization.yaml   image 6.14.1, 2 replicas, role demo-prod
```

Overlays hold **only the differences**. To see exactly what Argo CD will
apply:

```bash
kubectl kustomize gitops/apps/demo/overlays/prod
diff <(kubectl kustomize gitops/apps/demo/overlays/dev) \
     <(kubectl kustomize gitops/apps/demo/overlays/prod)
```

Kustomize vs Helm, briefly: Helm for software you *distribute* (OpenBao,
ESO, Argo CD are installed from charts here); Kustomize for your *own* apps
across environments. Both are common, often together.

## The ApplicationSet

[`demo.yaml`](../gitops/root/appsets/demo.yaml) uses the Git directory
generator: one Application per folder matching
`gitops/apps/demo/overlays/*`. `{{ .path.basename }}` becomes `dev` or
`prod` in the app name and namespace.

Things it sets for every generated app:

- `project: apps`, the restricted AppProject.
- `CreateNamespace=true` with `managedNamespaceMetadata` labels that turn on
  Pod Security Admission `restricted`. Look at the Deployment's
  `securityContext`: non-root, read-only root filesystem, no capabilities,
  seccomp. Without those, PSA would reject the pods.
- `preserveResourcesOnDeletion: true`: deleting the ApplicationSet does not
  cascade-delete running environments. A safety net worth having in prod.

## Exercise 1: promote dev → prod

Prod runs `6.14.1`, dev runs `6.15.0`. Check:

```bash
source scripts/env.sh
for e in dev prod; do
  kubectl -n demo-$e get deploy demo -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
done
```

Promote: edit `gitops/apps/demo/overlays/prod/kustomization.yaml`, set
`newTag: "6.15.0"`, then:

```bash
git commit -am "Promote demo 6.15.0 to prod"
make push
kubectl -n demo-prod rollout status deploy/demo
```

In a team this is a pull request. The PR *is* the change request, the
approval and the audit trail.

## Exercise 2: add an environment

```bash
cp -r gitops/apps/demo/overlays/dev gitops/apps/demo/overlays/staging
sed -i '' 's/dev/staging/g' gitops/apps/demo/overlays/staging/kustomization.yaml
```

Before pushing, give staging its OpenBao role and secret: add a `demo-staging`
entry to `tenants` in
[`infra/stacks/20-openbao-config/variables.tf`](../infra/stacks/20-openbao-config/variables.tf)
and run `make openbao-config`. Then commit and `make push`. A new
`demo-staging` app appears, in a new namespace, with its own secret.

That's the onboarding flow you'd hand to product teams: one OpenTofu
entry for the secrets side, one folder for the Kubernetes side. (In a
mature setup both live in one PR and CI applies the OpenTofu part.)

To remove it: delete the folder, push (Argo CD prunes the app), then remove
the tenant entry and apply stack 20.

## Exercise 3: break it and read the signals

Set `image: ghcr.io/stefanprodan/podinfo:does-not-exist` in the dev overlay
(`newTag: does-not-exist`) and push. In the UI the app is **Synced** (Git was
applied) but **Degraded** (pods can't pull). That distinction is the most
useful thing in Argo CD's UI. Revert and push.

Next: [08 · Day 2 operations](08-day-2-operations.md)
