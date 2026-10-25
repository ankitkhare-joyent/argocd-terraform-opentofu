# Lab 04 · OpenBao: a secrets manager that starts itself

One sitting, about 30 minutes. Background: [docs/03](../docs/03-openbao-how-it-works.md) and
[docs/06](../docs/06-step-3-openbao-and-secrets.md). Code:
[gitops/platform/openbao/values.yaml](../gitops/platform/openbao/values.yaml),
[infra/stacks/20-openbao-config/](../infra/stacks/20-openbao-config/).

After this lab you can explain:

- how OpenBao unseals itself, and what would change with a cloud KMS
- what self-initialization did on first boot, and where the root token went
- who your token is, what it may do, and what an app's policy allows

## Before you start

```bash
source lab/env.sh
bao token lookup > /dev/null && echo "token ok" || make bao-login
```

## 1. Is it open?

**Predict (P1):** is OpenBao sealed? What seal type is it using, and how many key shares would a human need to type
to unseal it?

```bash
curl -s $BAO_ADDR/v1/sys/health | jq -c '{initialized, sealed, standby, version}'
curl -s $BAO_ADDR/v1/sys/seal-status | jq -c '{type, t, n, recovery_seal, storage_type}'
```

Neither endpoint needs a token: load balancers and probes call them.

## 2. Who am I?

**Predict (P2):** `make bao-login` logged you in as `tofu-admin` through userpass. Which policies does the token
carry, and how long does it live?

```bash
bao token lookup -format=json | jq -c '.data | {display_name, policies, ttl_min: (.ttl/60|floor), renewable}'
```

## 3. What's configured

**Predict (P3):** which auth methods and secrets engines exist? Which of them did self-init create, and which did
OpenTofu stack 20 create?

```bash
bao auth list -format=json | jq -c 'to_entries | map({path: .key, type: .value.type})'
bao secrets list -format=json | jq -c 'to_entries | map({path: .key, type: .value.type, ver: .value.options.version})'
```

## 4. What did self-init do, and as whom?

**Predict (P4):** the audit log records every request. Whose token made the self-init requests?

```bash
kubectl -n openbao logs openbao-0 \
  | grep -E '"path":"(sys/policies|auth/userpass/users|transit/keys)' \
  | jq -rc 'select(.type=="request") | [.request.path, .auth.display_name] | @tsv'
```

## 5. What may an app read?

**Predict (P5):** the dev app's policy and role. Which paths, which capabilities, which ServiceAccount, how long?

```bash
bao policy read demo-dev-read
bao read -format=json auth/kubernetes/role/demo-dev | jq -c '.data | {bound_service_account_names,
  bound_service_account_namespaces, token_policies, token_ttl}'
bao_keys apps/demo/dev
bao operator raft list-peers
```

## Break it, then fix it: kill OpenBao

Production pods restart. With Shamir keys, a person would now have to type key shares before any app could get a
secret.

**Predict (P6):** you delete the `openbao-0` pod. How long until OpenBao is unsealed again, and does anyone need to
do anything?

```bash
start=$(date +%s); kubectl -n openbao delete pod openbao-0 > /dev/null; echo "old pod gone after $(( $(date +%s)-start ))s"
until curl -s $BAO_ADDR/v1/sys/health 2>/dev/null | grep -q '"sealed":false'; do sleep 1; done
echo "unsealed after $(( $(date +%s)-start ))s total"
kubectl -n openbao logs openbao-0 | grep -v '^{' | grep -iE "vault is unsealed|unsealed with stored key"
bao_keys apps/demo/dev
```

Nothing to fix: that's the point. (Wait for `delete` to return before polling. Otherwise the old pod answers
"unsealed" and you measure nothing.)

## Check your predictions

**P1.** Open: `{"initialized":true,"sealed":false,"standby":false,"version":"2.7.1"}`. Seal status:
`{"type":"static","t":0,"n":0,"recovery_seal":true,"storage_type":"raft"}`. With auto-unseal there are no unseal
shares (`t` and `n` are 0) and no human step. In production the type would be `awskms` or similar. Same behavior,
but the key never leaves the KMS.

**P2.** `{"display_name":"userpass-tofu-admin","policies":["default","platform-admin"],"ttl_min":55,"renewable":true}`.
The role issues 1-hour tokens (`token_ttl = "1h"` in self-init), and 55 means it was a few minutes old.

**P3.** Auth: `kubernetes/`, `token/`, `userpass/`. Engines: `cubbyhole/`, `identity/`, `secret/` (kv v2), `sys/`,
`transit/`. Self-init created `userpass/` and `transit/`, the minimum for OpenTofu to log in and encrypt its state.
Stack 20 created `secret/` and `kubernetes/`. `token`, `cubbyhole`, `identity` and `sys` are built in.

**P4.** `root`:

```
sys/policies/acl/platform-admin   root
auth/userpass/users/tofu-admin    root
transit/keys/tofu-state           root
```

Self-init minted a root token, used it for exactly these requests and revoked it. Later lines show
`userpass-tofu-admin` (stack 20's requests).

**P5.** Read only, on one data path and its metadata:

```
path "secret/data/apps/demo/dev"     { capabilities = ["read"] }
path "secret/metadata/apps/demo/dev" { capabilities = ["read"] }
{"bound_service_account_names":["openbao-reader"],"bound_service_account_namespaces":["demo-dev"],
 "token_policies":["demo-dev-read"],"token_ttl":900}
```

`bao_keys` shows fields `["password","username"]`. Raft has one peer, `openbao-0`, `leader`, `Voter true`.

**P6.** The old pod took 8s to terminate. OpenBao was unsealed 10s after the delete, with no human involved:

```
core: vault is unsealed
core: unsealed with stored key
```

and the secret was readable straight away.

## What to remember

- Auto-unseal turns "pod restarted" from an incident into a non-event. The seal key is the crown jewel, so in
  production it lives in a KMS.
- Self-init means no root token ever exists outside the server.
- A role binds *who* (ServiceAccount + namespace) to *what* (policy). Read both when debugging access.
