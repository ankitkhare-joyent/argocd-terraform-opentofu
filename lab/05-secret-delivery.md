# Lab 05 · From OpenBao to a file in the pod

One sitting, about 35 minutes. Background: [docs/03](../docs/03-openbao-how-it-works.md) ("How a secret reaches
the demo pod") and [docs/06](../docs/06-step-3-openbao-and-secrets.md). Code:
[gitops/apps/demo/base/](../gitops/apps/demo/base/),
[infra/modules/openbao-app-tenant/](../infra/modules/openbao-app-tenant/).

After this lab you can explain:

- every hop a secret takes: OpenBao → External Secrets → Kubernetes Secret → pod
- how a pod's identity becomes an OpenBao token, and why dev can't read prod
- what a broken secret path looks like, and the Argo CD habit that bites while fixing it

## Before you start

```bash
source lab/env.sh
apps
```

## 1. Is everything synced?

**Predict (P1):** what do the ExternalSecrets and the dev SecretStore report? Who owns the `demo-db` Secret?

```bash
for e in demo-dev demo-prod; do printf '%-10s ' $e; es_status $e; done
kubectl -n demo-dev get secretstore openbao -o jsonpath='{.status.conditions[0].reason} {.status.capabilities}{"\n"}'
kubectl -n demo-dev get secret demo-db -o json | jq -c '{owner: .metadata.ownerReferences[0] | {kind,name}, keys: (.data|keys)}'
```

## 2. Log in the way External Secrets does

External Secrets asks Kubernetes for a short-lived token for the `openbao-reader` ServiceAccount and presents it
to OpenBao's Kubernetes auth method. You can do the same.

**Predict (P2):** what policies and TTL does the returned OpenBao token get?

```bash
JWT=$(kubectl -n demo-dev create token openbao-reader --duration=10m)
bao write -format=json auth/kubernetes/login role=demo-dev jwt="$JWT" | jq -c '.auth | {policies, lease_duration, meta: .metadata}'
T=$(bao write -field=token auth/kubernetes/login role=demo-dev jwt="$JWT")
```

**Predict (P3):** with that token, can you read dev? Prod?

```bash
BAO_TOKEN=$T bao kv get -format=json secret/apps/demo/dev | jq -c '.data.data | keys'
BAO_TOKEN=$T bao kv get secret/apps/demo/prod 2>&1 | grep -iE "denied|code"
```

**Predict (P4):** two more tries: the dev ServiceAccount asking for the *prod* role, and the dev namespace's
`default` ServiceAccount asking for the dev role.

```bash
bao write auth/kubernetes/login role=demo-prod jwt="$JWT" 2>&1 | tail -1
bao write auth/kubernetes/login role=demo-dev jwt="$(kubectl -n demo-dev create token default --duration=10m)" 2>&1 | grep Code
```

## 3. Same value at every hop

**Predict (P5):** compare fingerprints of the password in OpenBao, in the Kubernetes Secret, and in the file inside
the pod.

```bash
A=$(bao kv get -field=password secret/apps/demo/dev)
B=$(kubectl -n demo-dev get secret demo-db -o jsonpath='{.data.password}' | base64 -d)
C=$(kubectl -n demo-dev exec deploy/demo -- cat /etc/demo-db/password)
echo "openbao=$(fp "$A") k8s=$(fp "$B") pod=$(fp "$C")"; unset A B C
```

## Break it, then fix it: dev asks for prod's secret

Someone "fixes" a typo and points the dev ExternalSecret at `apps/demo/prod`.

**Predict (P6):** does Argo CD refuse the change? Does the dev app lose its Secret?

```bash
sed -i '' 's|value: apps/demo/dev|value: apps/demo/prod|' gitops/apps/demo/overlays/dev/kustomization.yaml
git commit -qam "lab05: dev reads prod path" && make push
argocd app get demo-dev --refresh > /dev/null
wait_app demo-dev Synced Degraded
es_status demo-dev
kubectl -n demo-dev get secret demo-db -o name
kubectl -n external-secrets logs deploy/external-secrets --since=3m | grep -o 'Code: 403[^"]*' | head -1
```

Fix it with a revert:

```bash
git revert --no-edit HEAD && make push
argocd app get demo-dev --refresh > /dev/null; sleep 20
argocd app get demo-dev -o json | jq -c '{sync: .status.sync.status, health: .status.health.status, op: .status.operationState.message}'
```

**Predict (P7):** is dev healthy again? If not, read `op`.

```bash
argocd app terminate-op demo-dev        # only if op says "Retrying attempt #…"
wait_app demo-dev; es_status demo-dev
```

## Check your predictions

**P1.** Both ExternalSecrets: `True  SecretSynced  secret synced`. SecretStore: `Valid ReadWrite`. The Secret is
owned by `{"kind":"ExternalSecret","name":"demo-db"}` with keys `["password","username"]`, so deleting the
ExternalSecret deletes the Secret (`creationPolicy: Owner`).

**P2.** `{"policies":["default","demo-dev-read"],"lease_duration":900,...}`, and `meta` names the role,
`service_account_name: openbao-reader` and `service_account_namespace: demo-dev`. The ServiceAccount's identity
became a 15-minute token with one narrow policy.

**P3.** Dev: `["password","username"]`. Prod: `Code: 403. Errors: * permission denied`.

**P4.** The dev ServiceAccount with the prod role: `* namespace not authorized`. The prod role is bound to namespace
`demo-prod`. The `default` ServiceAccount: `Code: 403`, because the role is bound to the name `openbao-reader` only.
Two independent locks.

**P5.** All three fingerprints match (`753a16fce6f8` when I ran it; yours will differ). The pod reads the same value
OpenBao holds, without anyone copying it.

**P6.** Argo CD applies it: Git is valid and the `apps` project allows ExternalSecrets. The app goes
`Synced/Degraded`, `es_status` says `False  SecretSyncedError  could not get secret data from provider`, and the
ESO log shows OpenBao's 403 on `GET .../secret/data/apps/demo/prod`. The `demo-db` Secret is **kept** with its last
good value, so running pods aren't hurt. OpenBao's policy was the guardrail, not Argo CD.

**P7.** Probably not at first. When I fixed it, dev stayed `OutOfSync/Degraded` with
`one or more synchronization tasks completed unsuccessfully. Retrying attempt #4`. The sync of the *bad* commit was
still retrying: wave -1 (the ExternalSecret) never got healthy, so it kept retrying that old revision and blocked the
new one. `argocd app terminate-op demo-dev` stopped it, auto-sync applied the fixed commit, and dev was
`Synced/Healthy` with `True  SecretSynced` within seconds.

## What to remember

- Kubernetes auth turns "which pod is this?" into "which OpenBao policy applies?". The role binds both name and
  namespace.
- A bad secret path degrades the app but keeps the last good Secret. Fix it in Git.
- After fixing a commit whose sync is retrying, terminate the old operation so the new commit can sync.
