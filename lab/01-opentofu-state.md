# Lab 01 · OpenTofu: three stacks, three encrypted state files

One sitting, about 30 minutes. Background: [docs/02](../docs/02-opentofu-for-terraform-users.md) and
[docs/04](../docs/04-step-1-cluster.md). Code: [infra/stacks/](../infra/stacks/), [infra/modules/](../infra/modules/).

OpenTofu comes first because it built everything else: the cluster, the secrets OpenBao boots from, Argo CD, and
OpenBao's configuration. After this lab you can explain:

- what is (and isn't) in an encrypted state file
- why the OpenBao seal key went into Kubernetes without ever touching state
- what it looks like when the state key is wrong, and when OpenBao is the key

Answers to every **Predict** are at the bottom. Nothing in this lab changes infrastructure: every OpenTofu command
is `state list`, `show` or `plan`.

## Before you start

```bash
source lab/env.sh
apps          # six apps, Synced / Healthy
```

## 1. What does a state file look like on disk?

**Predict (P1):** `.state/00-cluster.tfstate` is the state for one kind cluster. If you open it, will you see the
cluster's name and endpoint?

```bash
ls -lh .state/
jq 'keys' .state/00-cluster.tfstate
jq -r '.meta | keys[]' .state/00-cluster.tfstate
```

## 2. What does each stack own?

**Predict (P2):** how many resources does each stack track? Which stack has the most, and why is the cluster alone
in its own state?

```bash
for s in 00-cluster 10-bootstrap 20-openbao-config; do echo "== $s"; scripts/tofu.sh $s state list; done
```

`scripts/tofu.sh` loads the passphrase, so OpenTofu can decrypt. You just read encrypted state without noticing.

## 3. Where did the seal key go?

Stack 10 generated OpenBao's 32-byte seal key and wrote it into the `openbao-seal` Secret.

**Predict (P3):** does stack 10's state contain the key? What does it store for the Secret's data?

```bash
cd infra/stacks/10-bootstrap
tofu show -json | grep -c BAO_STATIC_UNSEAL_KEY
tofu show -json | jq '.values.root_module.resources[]
  | select(.address=="kubernetes_secret_v1.openbao_seal") | .values | {data, data_wo, data_wo_revision}'
cd -
```

Now read [10-bootstrap/main.tf](../infra/stacks/10-bootstrap/main.tf) and find `ephemeral "random_bytes"` and
`data_wo_revision`.

## 4. Is everything in sync?

**Predict (P4):** the ephemeral resource generates a *new* random key on every run. So does `plan` on stack 10
want to replace the seal key each time?

```bash
scripts/tofu.sh 10-bootstrap plan -input=false -detailed-exitcode > /tmp/plan10.txt; echo "exit=$?"; tail -3 /tmp/plan10.txt
scripts/tofu.sh 20-openbao-config plan -input=false | tail -3
```

`-detailed-exitcode` returns 0 for no changes, 2 for changes, 1 for an error: what CI uses to detect drift.

## Break it, then fix it

### Break 1: the wrong state key

**Predict (P5):** what does OpenTofu do with a state it can't decrypt: ignore it and plan to create the cluster
again, or stop?

```bash
TF_VAR_state_passphrase=wrong-passphrase-123456 bash -c 'cd infra/stacks/00-cluster && tofu plan -input=false' 2>&1 | grep -iE "error|decrypt" | head -4
```

The fix is having the right key, which `source lab/env.sh` gives you back. Nothing was changed: OpenTofu stopped
before planning anything.

### Break 2: OpenBao is the key

Stack 20's state is encrypted with OpenBao's transit engine (see its
[versions.tf](../infra/stacks/20-openbao-config/versions.tf)).

**Predict (P6):** what happens to `plan` in stack 20 with no OpenBao token?

```bash
(unset BAO_TOKEN VAULT_TOKEN; cd infra/stacks/20-openbao-config && tofu plan -input=false 2>&1 | grep -iE "error|403" | head -4)
```

Fix: none needed, your shell still has the token. When it expires (1 hour) you'll see the same error for real:
`make bao-login && source lab/env.sh`.

## Check your predictions

**P1.** No. The file has five top-level keys: `encrypted_data`, `encryption_version`, `lineage`, `meta`, `serial`.
`meta` only names the key provider (`key_provider.pbkdf2.local`) and its salt. The cluster's name and endpoint are
inside `encrypted_data`. Files are small: 17K (00), 30K (10), 20K (20).

**P2.** 1, 7 and 10:

```
00-cluster        module.cluster.kind_cluster.this
10-bootstrap      kubernetes_namespace_v1.openbao, kubernetes_secret_v1.openbao_bootstrap_admin,
                  kubernetes_secret_v1.openbao_seal, module.argocd.helm_release.argocd,
                  module.argocd.helm_release.root, module.argocd.kubernetes_namespace_v1.argocd,
                  module.argocd.kubernetes_secret_v1.repo
20-openbao-config vault_auth_backend.kubernetes, vault_kubernetes_auth_backend_config.this, vault_mount.kv,
                  vault_policy.tofu_plan, and per tenant (demo-dev, demo-prod): auth role, kv seed, policy
```

The cluster is alone because a cluster replacement must never ride along with an unrelated change. kind can't even
modify a cluster in place, so any change to it plans a replace.

**P3.** No. `grep -c` prints `0`, and the resource shows:

```json
{ "data": null, "data_wo": null, "data_wo_revision": 1 }
```

The value went to the Kubernetes API and nowhere else. OpenTofu keeps only the revision number, which is the only
thing it can compare.

**P4.** No. Both plans say `No changes. Your infrastructure matches the configuration.` (exit 0). A write-only value
is sent again only when its revision changes, so a fresh random key is generated and thrown away each run. That's
also why you must never bump `data_wo_revision` on the seal key of a live OpenBao: it would replace the key that
unlocks its data.

**P5.** It stops:

```
Error: Error acquiring the state lock
... decryption failed for all ...
attempted decryption failed for state: decryption failed: cipher: message authentication failed
```

AES-GCM authenticates as well as encrypts, so a wrong key is detected, not silently misread.

**P6.** It can't even read its state:

```
Error: Unable to fetch encryption key data
key_provider.openbao.transit failed with error: failed to generate OpenBao
error sending datakey request to OpenBao: Error making API request.
Code: 403. Errors:
```

Losing access to OpenBao means losing access to this stack's state. That's the trade-off of using it as the key.

## What to remember

- Encrypted state hides everything but a few metadata fields. Keep the key somewhere safer than the state.
- Ephemeral values plus write-only attributes keep secrets out of state entirely. Rotation is a revision bump.
- One state per layer keeps blast radius small, and `plan -detailed-exitcode` is how CI notices drift.
