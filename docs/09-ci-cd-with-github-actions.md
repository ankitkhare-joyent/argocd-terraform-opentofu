# 09 · CI/CD with GitHub Actions

You already know GitHub Actions, so this page is about *what changes* when
Argo CD and OpenBao are in the picture. The short version: **CI stops
deploying.** CI tests, builds, and opens pull requests. Argo CD deploys.

## The two pipelines

```
 App repo                               Platform repo (this one)
 ────────                               ────────────────────────
 push ─▶ test ─▶ build image ─▶ push    PR ─▶ validate.yml (fmt, render, schemas)
         to registry (tag = git SHA)          tofu.yml   (plan, PR comment)
                │                         merge ─▶ tofu.yml (apply, after approval)
                └─▶ open PR here:              ─▶ Argo CD notices the commit
                    "bump demo dev to <sha>"        and syncs the cluster
```

Nothing in either pipeline holds a kubeconfig. That is the security win.

## Workflows in this repo

| File | Trigger | Credentials needed |
|---|---|---|
| [`validate.yml`](../.github/workflows/validate.yml) | Every PR | None |
| [`tofu.yml`](../.github/workflows/tofu.yml) | PRs and pushes touching stack 20 | GitHub OIDC token only |

`validate.yml` runs [`scripts/validate.sh`](../scripts/validate.sh), the same
script `make validate` runs locally: `tofu fmt -check`, `tofu validate` on
every stack, `kustomize build` of every overlay piped into `kubeconform`
(schema validation, including CRDs like ExternalSecret from the community
CRD catalog). Catching a typo here is much cheaper than finding a
`ComparisonError` in Argo CD.

## Keyless CI: GitHub OIDC → OpenBao

Every GitHub Actions job can request a signed JWT from GitHub describing
itself (`repository`, `ref`, `event_name`, `environment`, `sha`, ...).
OpenBao's `jwt` auth method verifies the signature against GitHub's public
keys and matches the claims against a role:

```hcl
# infra/stacks/20-openbao-config/main.tf
resource "vault_jwt_auth_backend_role" "tofu_ci" {
  role_name    = "tofu-ci"
  bound_claims = {
    repository = var.github_repository
    ref        = "refs/heads/main"   # only main can apply
  }
  token_policies = ["platform-admin"]
  token_ttl      = 900
}
```

and a second role, `tofu-ci-plan`, bound to `event_name = pull_request`
with a read-only policy. A PR from a fork, or a PR that edits the workflow
file, can at most run a plan.

The same pattern gives CI short-lived AWS credentials (`aws-actions/configure-aws-credentials`
with an IAM role trusting GitHub's OIDC provider). No long-lived cloud keys
in GitHub secrets is now the baseline expectation in interviews.

To turn it on for a real repo: `tofu apply -var github_repository=you/your-repo`
in stack 20.

## Promotion between environments

Promotion is a Git change to the overlay:

```yaml
# gitops/apps/demo/overlays/prod/kustomization.yaml
images:
  - name: ghcr.io/stefanprodan/podinfo
    newTag: "6.15.0"   # was 6.14.1
```

Ways teams automate that PR:

- The app's CI opens it (`kustomize edit set image ...` + `gh pr create`).
- **Argo CD Image Updater** watches the registry and commits new tags.
- **Kargo** (from the Argo CD creators) models stages and promotion rules
  explicitly. Worth a look once the basics are solid.

## Seeing the real diff in a PR

`kustomize build` output is what reviewers *should* look at, but a
three-line values change can render a large manifest diff. Options:

- `argocd app diff demo-prod --local gitops/apps/demo/overlays/prod`
  (needs Argo CD access, so usually from a self-hosted runner).
- `argocd-diff-preview` (community tool) renders before/after in an
  ephemeral kind cluster inside the CI job and comments the diff.
- **Source Hydrator** (beta in Argo CD 3.5): Argo CD commits fully rendered
  manifests to an environment branch, so the PR diff *is* the rendered diff.

Next: [10 · Production checklist](10-production-checklist.md)
