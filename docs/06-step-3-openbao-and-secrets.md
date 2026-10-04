# 06 · Step 3: OpenBao and secrets (stack 20)

**Goal:** see OpenBao start itself with no human in the loop, configure it
with OpenTofu, and follow one secret from OpenBao into a running pod.

**Files:** [`gitops/platform/openbao/values.yaml`](../gitops/platform/openbao/values.yaml),
[`infra/stacks/20-openbao-config/`](../infra/stacks/20-openbao-config/),
[`infra/modules/openbao-app-tenant/`](../infra/modules/openbao-app-tenant/),
[`gitops/apps/demo/base/`](../gitops/apps/demo/base/)

## Part A: OpenBao starts itself

Argo CD installed OpenBao in step 2. Nobody ran `bao operator init` or typed
an unseal key. Read the `config:` block in
[`values.yaml`](../gitops/platform/openbao/values.yaml) top to bottom:

1. `storage "raft"`: integrated storage, HA-ready.
2. `seal "static"`: auto-unseal from `BAO_STATIC_UNSEAL_KEY`, which the pod
   gets from the Secret OpenTofu made in step 2.
3. `audit "file" "stdout"`: every request is logged, declared in config.
4. `initialize "admin"` and `initialize "state-encryption"`: on first boot,
   OpenBao runs these API calls with a temporary root token and then revokes
   it. They create a `platform-admin` policy, a `tofu-admin` login whose
   password comes from `INITIAL_ADMIN_PASSWORD`, and a transit key.

```bash
source scripts/env.sh
curl -s $BAO_ADDR/v1/sys/health | jq     # initialized: true, sealed: false
# The audit log (JSON lines on stdout) shows self-init's requests, made with
# a root token that was revoked straight afterwards:
kubectl -n openbao logs openbao-0 \
  | grep -E '"path":"(sys/policies|auth/userpass/users|transit/keys)' \
  | jq -rc '[.type, .request.path, .auth.display_name] | @tsv'
```

Secret values in the audit log are HMAC'd, never plain.

## Part B: configure OpenBao with OpenTofu

```bash
make bao-login        # userpass login → .secrets/bao-token (1h TTL)
make openbao-config   # stack 20
```

### Read [`20-openbao-config/versions.tf`](../infra/stacks/20-openbao-config/versions.tf)

This stack's state is encrypted with `key_provider "openbao"`: OpenTofu asks
OpenBao's transit engine for a data key. Without a valid OpenBao token you
can't even run `tofu plan` here. The tool that configures your secrets
manager is itself protected by it.

### Read [`20-openbao-config/main.tf`](../infra/stacks/20-openbao-config/main.tf)

- A KV v2 mount at `secret/`.
- The Kubernetes auth method, configured to call the cluster's TokenReview
  API.
- `module "tenant"` with `for_each = var.tenants`: one call per app and
  environment.
- GitHub OIDC auth roles for CI (off unless you set `github_repository`; see
  doc 09).

### Read [`modules/openbao-app-tenant/main.tf`](../infra/modules/openbao-app-tenant/main.tf)

Per tenant: a read-only policy for exactly one path, a Kubernetes auth role
bound to exactly one ServiceAccount in one namespace, and the initial secret
written with `data_json_wo`, so the password exists only in OpenBao.

Onboarding a new app or environment is adding one entry to `tenants` in
[`variables.tf`](../infra/stacks/20-openbao-config/variables.tf).

## Part C: follow the secret into the pod

```
OpenBao secret/apps/demo/dev
  → SecretStore "openbao" (namespace demo-dev, role demo-dev, SA openbao-reader)
  → ExternalSecret "demo-db"
  → Secret "demo-db"
  → pod: env DB_USERNAME + file /etc/demo-db/password
```

```bash
# 1. In OpenBao
bao kv get secret/apps/demo/dev

# 2. ESO's view
kubectl -n demo-dev get secretstore,externalsecret
kubectl -n demo-dev describe externalsecret demo-db | tail -5

# 3. The Kubernetes Secret ESO created
kubectl -n demo-dev get secret demo-db -o jsonpath='{.data.username}' | base64 -d; echo

# 4. Inside the app (podinfo shows files under its config path)
kubectl -n demo-dev port-forward svc/demo 9898:80 &
curl -s localhost:9898/configs | jq
curl -s localhost:9898/env | jq -r '.[]' | grep DB_USERNAME
kill %1
```

## Things to try

1. **Isolation.** Edit `gitops/apps/demo/overlays/dev/kustomization.yaml` so
   the ExternalSecret key is `apps/demo/prod`. Push. The ExternalSecret goes
   `SecretSyncedError`: the dev role's token gets *permission denied* from
   OpenBao. Revert and push.
2. **No plain Secrets allowed.** Add a `Secret` manifest to the dev overlay
   and push. Argo CD refuses it: the `apps` AppProject blacklists the
   `Secret` kind. Revert.
3. **No password in state.** In `infra/stacks/20-openbao-config`, run
   `tofu show -json | grep -c '"password"'`. The count is 0.
4. **Log in as the app would.** Get a token the way ESO does:

   ```bash
   JWT=$(kubectl -n demo-dev create token openbao-reader)
   bao write auth/kubernetes/login role=demo-dev jwt="$JWT"
   ```

   Use the returned token to read dev (works) and prod (denied).

Next: [07 · Step 4, apps and promotion](07-step-4-apps-and-promotion.md)
