# 02 · OpenTofu for Terraform users

You already know 95% of OpenTofu. It is the Linux Foundation fork of
Terraform 1.5, created in 2023 when HashiCorp moved Terraform to the
Business Source License. Same HCL, same providers, same state format at the
fork point. You run `tofu` instead of `terraform`.

This page is only about what is **different**, and which of those
differences this lab uses on purpose.

## Why teams pick it

- **License**: MPL-2.0, governed by the Linux Foundation / CNCF. No vendor can
  change the terms later. This was the reason most companies first looked.
- **Features Terraform doesn't have** (below). Several are now the reason
  teams stay.
- **Drop-in**: existing `.tf` code, modules and providers work. Migration is
  usually `terraform` → `tofu` in CI plus re-running `init`.

Terraform is still more common in job ads overall, so learning OpenTofu does
not replace knowing Terraform. In practice you list both: the skills transfer
one-to-one, and OpenTofu adoption keeps growing, especially at companies that
care about open source licensing.

## What's different, and where this lab uses it

### 1. Client-side state encryption (OpenTofu 1.7+)

Terraform state is plaintext JSON containing every attribute of every
resource, often including passwords. Terraform relies on the backend (S3
SSE, for example) to protect it, so anyone who can read the bucket can read
your secrets.

OpenTofu encrypts state and plan files **before** they leave the process:

```hcl
terraform {
  encryption {
    key_provider "pbkdf2" "local" { passphrase = var.state_passphrase }
    method "aes_gcm" "local"      { keys = key_provider.pbkdf2.local }
    state { method = method.aes_gcm.local, enforced = true }
    plan  { method = method.aes_gcm.local, enforced = true }
  }
}
```

Key providers: `pbkdf2` (passphrase), `aws_kms`, `gcp_kms`, `azure_vault`,
`openbao`, `external`. `fallback {}` blocks let you rotate keys or migrate
an existing unencrypted state.

Used in: [`infra/stacks/00-cluster/versions.tf`](../infra/stacks/00-cluster/versions.tf)
(pbkdf2) and
[`infra/stacks/20-openbao-config/versions.tf`](../infra/stacks/20-openbao-config/versions.tf)
(`openbao` transit key, so OpenBao guards the state of the stack that
configures OpenBao).

Try it: `jq 'keys' .state/00-cluster.tfstate` shows only `encrypted_data`, `meta`,
`lineage`, `serial` and `encryption_version`. Your resources are inside
`encrypted_data`, unreadable without the key.

### 2. Early variable evaluation (1.8+)

Variables and locals are allowed in places Terraform forbids: the
`encryption` block, `backend` blocks, module `source` and `version`. That is
how the passphrase above comes from `var.state_passphrase` instead of being
hard-coded.

### 3. Ephemeral values and write-only attributes (1.11+)

The modern answer to "secrets in state":

- `ephemeral "random_password" "x" {}` produces a value that exists only
  during this run. It is never written to state or plan.
- `variable "token" { ephemeral = true }` does the same for inputs.
- Write-only attributes (`*_wo`) accept ephemeral values, send them to the
  API, and store nothing. Because OpenTofu can't diff a value it never kept,
  each has a companion `*_wo_version` / `*_wo_revision` number you bump to
  force a re-write (that's your rotation trigger).

Used in:
- [`infra/stacks/10-bootstrap/main.tf`](../infra/stacks/10-bootstrap/main.tf):
  the OpenBao seal key and admin password go into Kubernetes Secrets via
  `data_wo`.
- [`infra/modules/openbao-app-tenant/main.tf`](../infra/modules/openbao-app-tenant/main.tf):
  app passwords go into OpenBao via `data_json_wo`.

Check it yourself after `make up`: decrypting and grepping the state finds
no password anywhere.

Terraform added ephemeral values too (1.10/1.11), so this pattern is
portable knowledge.

### 4. Smaller things you'll meet

| Feature | Version | What it does |
|---|---|---|
| `for_each` on `provider` blocks | 1.9 | One provider config per region/account from a map |
| `-exclude` flag | 1.9 | Inverse of `-target` |
| OCI registry for providers/modules | 1.10 | Mirror providers in your own container registry (air-gapped orgs) |
| Native S3 locking (`use_lockfile = true`) | 1.10 | No DynamoDB lock table needed |
| `enabled` meta-argument | 1.11 | Cleaner than `count = var.x ? 1 : 0` |
| `.tofu` file extension | 1.8 | A `.tofu` file overrides the `.tf` with the same name, for code shared by both tools |

### 5. Registry

Providers come from `registry.opentofu.org`, which mirrors the public
providers (including `hashicorp/*`). Nothing to change in
`required_providers`.

## How this repo structures OpenTofu (and why)

```
infra/
  modules/                 reusable, versionable building blocks
    kind-cluster/          (would be an EKS module in the cloud)
    argocd-bootstrap/      Argo CD + Git credentials + root app
    openbao-app-tenant/    policy + auth role + seeded secret for one app/env
  stacks/                  one state file each, applied in order
    00-cluster/
    10-bootstrap/
    20-openbao-config/
```

**Stacks** (also called layers, root modules or components) split state by
blast radius and rate of change. A bad change to an app's secret policy can
never plan a cluster replacement, because the cluster isn't in that state.
Each stack also gets its own CI job and its own permissions. Stacks talk to
each other through stable interfaces (a kubeconfig file, an API address),
not through `terraform_remote_state`, which couples states tightly.

**Modules** are small and do one thing. Callers pass in everything
environment-specific, so the same module runs in dev and prod.

**Pinned versions everywhere**: `required_version`, provider `~>`
constraints, committed `.terraform.lock.hcl` files (locked for both
`darwin_arm64` and `linux_amd64` so CI matches your laptop), and pinned CLI
versions in [`mise.toml`](../mise.toml).

## What OpenTofu manages here vs what Argo CD manages

The rule most platform teams converge on:

- **OpenTofu**: things outside Kubernetes (cloud networks, clusters, IAM,
  DNS, databases) and API configuration of external systems (OpenBao policies
  and roles, Gitea repos, Datadog monitors). Also the minimal bootstrap that
  must exist before GitOps can start.
- **Argo CD**: everything that is a Kubernetes object, after bootstrap.

Avoid managing the same object from both. That is why stack 10 has
`ignore_changes = [values, version]` on the Argo CD release: once Argo CD
manages itself, OpenTofu should not fight it.

Next: [03 · How OpenBao works](03-openbao-how-it-works.md)
