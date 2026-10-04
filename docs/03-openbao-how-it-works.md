# 03 · How OpenBao works

OpenBao is the Linux Foundation fork of HashiCorp Vault (forked from Vault
1.14 in late 2023, after Vault's license change). It keeps Vault's HTTP API,
so the Vault CLI, the Terraform `vault` provider, External Secrets Operator's
`vault` provider and most client libraries work against it unchanged. The CLI
is called `bao`.

If you have never used Vault: it is a server that stores secrets encrypted,
hands them out only to authenticated callers whose policy allows it, logs
every access, and can generate short-lived credentials on demand.

## The five ideas you need

### 1. Barrier, seal and unseal

Everything OpenBao writes to storage passes through an encryption **barrier**
(AES-256-GCM). The barrier key is itself encrypted by a **root key**, and the
root key is encrypted by the **seal**.

```
   storage (Raft on disk)
        ▲  ciphertext only
   ┌────┴─────┐
   │ barrier  │  ← encryption key (in memory only while unsealed)
   └────┬─────┘
        │ decrypted by
   root key
        │ decrypted by
   seal  ── Shamir key shares (humans), or
          ── auto-unseal: a KMS (AWS KMS, GCP KMS, Azure Key Vault, PKCS#11,
             another OpenBao's transit engine) or, in this lab, a "static" key
```

When an OpenBao pod starts it is **sealed**: it has the encrypted data but
can't read it. With Shamir, N humans each type a key share. With
**auto-unseal**, OpenBao asks the KMS to decrypt the root key and is ready
in seconds. Production clusters use auto-unseal because pods restart.

This lab uses `seal "static"`: the key is a 32-byte value from an
environment variable, which OpenTofu put into a Kubernetes Secret. It
behaves exactly like KMS auto-unseal, which is the point, but the key lives
next to the data, so it is **not** a production setup. Swap it for
`seal "awskms" { kms_key_id = "..." }` on EKS (using IRSA or Pod Identity
for credentials) and nothing else changes.

See it: `make stop && make start`, then watch OpenBao report
`sealed: false` on its own.

### 2. Storage: integrated Raft

OpenBao stores data in its own Raft cluster (`storage "raft"`), so it needs
no Consul or external database. Production runs 3 or 5 replicas across
availability zones; one is the leader, the others replicate and take over on
failure. This lab runs the same HA configuration with 1 replica.

### 3. Auth methods: how callers prove who they are

Callers never share one magic token. Each kind of caller logs in with what it
already has, and receives a short-lived OpenBao token:

| Auth method | Who uses it | Proof presented | In this lab |
|---|---|---|---|
| `kubernetes` | Pods | Their ServiceAccount JWT. OpenBao validates it with the Kubernetes TokenReview API | External Secrets, per namespace |
| `jwt` / `oidc` | CI jobs, humans via SSO | A signed JWT (GitHub Actions OIDC, Okta, Entra ID) | GitHub Actions role, defined in stack 20 (off by default) |
| `userpass` | Break-glass admin | Username + password | `tofu-admin`, created by self-init |
| `aws`, `gcp`, `azure` | Cloud workloads | Signed cloud identity | (not used) |
| `approle` | Legacy machines | Role ID + secret ID | (avoid for new work) |

### 4. Policies: what a token may do

Policies are deny-by-default path rules. The demo app's dev policy, generated
by [`openbao-app-tenant`](../infra/modules/openbao-app-tenant/main.tf):

```hcl
path "secret/data/apps/demo/dev"     { capabilities = ["read"] }
path "secret/metadata/apps/demo/dev" { capabilities = ["read"] }
```

A **role** on an auth method binds an identity to policies. The
`demo-dev` Kubernetes role says: "a JWT for ServiceAccount `openbao-reader`
in namespace `demo-dev` gets a 15-minute token with policy
`demo-dev-read`." Nothing in `demo-dev` can read `apps/demo/prod`.

### 5. Secrets engines: where secrets come from

- **KV v2** (`secret/`): versioned key/value store. Static secrets you put
  in. Used by this lab.
- **Transit** (`transit/`): encryption as a service. OpenBao keeps the key,
  you send plaintext and get ciphertext. Used by OpenTofu here to encrypt
  stack 20's state.
- **Database**: OpenBao creates a *new database user per request* with a TTL
  and drops it on expiry. This is the gold standard for DB credentials;
  the natural next step after this lab.
- **PKI**: issue short-lived TLS certificates (often paired with
  cert-manager).
- **AWS/GCP/Azure**: mint short-lived cloud credentials.

## Things OpenBao has that Vault OSS doesn't

- **Declarative self-initialization** (used here). The server config contains
  `initialize` blocks with API requests to run once on first start. No root
  token is ever printed; it is used for those requests and revoked. Values
  can come from env vars or files, so the config itself has no secrets. See
  [`gitops/platform/openbao/values.yaml`](../gitops/platform/openbao/values.yaml).
- **Declarative audit devices** in the config file (used here).
- **Namespaces** (multi-tenancy), which are an Enterprise-only feature in Vault.
- **The static seal** (used here) and pluggable auto-unseal.

## How a secret reaches the demo pod

```
 OpenTofu (stack 20) ──writes once──▶ OpenBao  secret/apps/demo/dev
                                          ▲
           (3) read with token            │ (2) login: SA JWT ──▶ TokenReview
                                          │
 External Secrets Operator ───────────────┘
   watches ExternalSecret "demo-db" in demo-dev,
   uses SecretStore "openbao" (role demo-dev, SA openbao-reader)
        │
        │ (4) creates/updates Kubernetes Secret "demo-db"
        ▼
 demo pod ── env var DB_USERNAME (read at start)
          └─ volume /etc/demo-db (kubelet refreshes the file in place)
```

Every `refreshInterval` (1 minute here) ESO re-reads OpenBao, so a rotated
value flows to the Secret automatically.

## Why External Secrets Operator and not the alternatives

| Approach | How | When it fits |
|---|---|---|
| **External Secrets Operator** (this lab) | Controller syncs into native K8s Secrets | Default choice. Apps need no changes, works with any chart, Argo CD shows status. Downside: the value exists as a K8s Secret (protect etcd with encryption at rest + RBAC). |
| OpenBao Agent Injector | Sidecar writes secrets to a shared volume | When you want no K8s Secret at all, or need templating/dynamic leases renewed by the agent |
| Secrets Store CSI driver | Mounts secrets as a volume via CSI | Similar to the injector without a sidecar |
| App calls OpenBao API directly | SDK in the app | Dynamic secrets with fine-grained lease handling |
| Sealed Secrets / SOPS | Encrypted secret committed to Git | Small setups without a secrets manager. No central audit, rotation or revocation |

The rule this lab enforces with the `apps` AppProject: **no Secret objects in
Git at all**. Git holds only `ExternalSecret` references, and the values
live in OpenBao.

## The "secret zero" problem

Something must exist before the secrets manager does. Here that is exactly two
values, created by OpenTofu in stack 10 and never written to its state:
the seal key and the first admin password. In the cloud, the seal key becomes
a KMS key that never leaves AWS, and the admin password becomes "nobody has
one; CI logs in with OIDC, humans with SSO". Reducing secret zero to cloud
IAM is the goal.

Next: [04 · Step 1, the cluster](04-step-1-cluster.md)
