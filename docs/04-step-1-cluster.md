# 04 · Step 1: the cluster (stack 00)

**Goal:** create the Kubernetes cluster with OpenTofu, and see state
encryption working.

**Files:** [`infra/stacks/00-cluster/`](../infra/stacks/00-cluster/),
[`infra/modules/kind-cluster/`](../infra/modules/kind-cluster/)

## Run it

```bash
make cluster
```

This runs `scripts/tofu.sh 00-cluster apply`, which loads
[`scripts/env.sh`](../scripts/env.sh) first. That script:

- points `KUBECONFIG` at `.kube/config` inside this folder (your
  `~/.kube/config` is never touched),
- generates `.secrets/state-passphrase` once and exports it as
  `TF_VAR_state_passphrase`.

If the Docker VM is busy, `make up` stops at the pre-flight check
([`scripts/preflight.sh`](../scripts/preflight.sh)) with a clear message
instead of failing deep inside kubeadm.

## Read the code in this order

1. **[`versions.tf`](../infra/stacks/00-cluster/versions.tf)**: provider pins
   and the `encryption` block. `enforced = true` means OpenTofu refuses to
   write an unencrypted state, even by mistake.
2. **[`backend.tf`](../infra/stacks/00-cluster/backend.tf)**: local state in
   `.state/`, with the S3 production version in comments. Note
   `use_lockfile = true`: S3 now locks natively, no DynamoDB table.
3. **[`main.tf`](../infra/stacks/00-cluster/main.tf)**: calls the module with
   port mappings for Argo CD (48080) and OpenBao (48200).
4. **[`modules/kind-cluster/main.tf`](../infra/modules/kind-cluster/main.tf)**:
   one control-plane node, `dynamic` blocks for ports and optional workers.

The module's interface (name and version in; kubeconfig and endpoint out) is
the same shape an EKS module has. Replacing kind with EKS later changes this
module, not the stacks that use the cluster.

## See it

```bash
source scripts/env.sh
kubectl get nodes -o wide
docker ps --filter name=platform-control-plane   # the "node" is a container

head -c 200 .state/00-cluster.tfstate; echo       # ciphertext, not JSON
cd infra/stacks/00-cluster && tofu show | head    # tofu decrypts it for you
```

## Things to try

- Run `make cluster` again. The plan says *No changes*. That idempotency is
  what lets the scripts be re-run safely.
- Remove `TF_VAR_state_passphrase` from your shell (`unset
  TF_VAR_state_passphrase`) and run `tofu plan`. It fails: without the key,
  the state is unreadable.
- Change `worker_count` to 1 in `main.tf` and `tofu plan`. kind can't modify a
  cluster in place, so it plans a **replace**. That is exactly why the
  cluster lives in its own stack: a cluster replacement should never ride
  along with an unrelated change.

## Interview angle

"Why separate state per layer?" Blast radius, plan speed, different change
cadence, and separate permissions (the stack that creates clusters needs far
more cloud rights than the one that configures OpenBao).

Next: [05 · Step 2, Git and the Argo CD bootstrap](05-step-2-bootstrap.md)
