# 10 · From this lab to production

Every shortcut this lab takes is listed here with what replaces it. Use it as
a design review checklist, and as interview material: "what would you change
before running this for real?" is the question.

## Lab shortcut → production equivalent

| Area | In this lab | In production |
|---|---|---|
| Cluster | kind, 1 node, OpenTofu `tehcyx/kind` | EKS/GKE/AKS via OpenTofu module; managed node groups or Karpenter; 3 AZs |
| Git | Gitea container, one repo | GitHub/GitLab; branch protection, required reviews, CODEOWNERS on `gitops/` and `infra/` |
| Argo CD access | NodePort, plain HTTP, local admin | Ingress + TLS, SSO via OIDC (Okta/Entra/Google), `admin.enabled: false`, RBAC groups |
| Argo CD scale | 1 replica each | HA values: redis-ha, 2+ server and repo-server replicas, controller sharding for many clusters |
| Argo CD topology | In-cluster only | Hub-and-spoke (one Argo CD manages many clusters) or one per cluster; cluster generator ApplicationSets |
| Git sync | Poll every 60s | Webhook from GitHub, polling as fallback |
| Notifications | Off | argocd-notifications to Slack on sync failure / degraded health |
| OpenBao seal | `static` key in a K8s Secret | `awskms` / `gcpckms` / `azurekeyvault` with workload identity; key never leaves KMS |
| OpenBao HA | Raft, 1 replica | Raft, 3 or 5 replicas, pod anti-affinity across zones, PodDisruptionBudget |
| OpenBao TLS | Disabled | cert-manager-issued certs, `tls_disable = 0`, clients verify CA |
| OpenBao backups | None | Scheduled Raft snapshots to object storage (the chart's snapshot agent), restore drills |
| OpenBao admin | `tofu-admin` userpass | No standing admin. CI via JWT/OIDC, humans via OIDC SSO with MFA; userpass kept only as sealed break-glass |
| OpenBao audit | stdout | stdout shipped to SIEM, plus a second audit device (if all devices fail, OpenBao refuses requests) |
| DB credentials | Static random password in KV | Database secrets engine: per-pod dynamic users with TTL |
| Kubernetes Secrets | Default etcd storage | Encryption at rest with KMS (EKS envelope encryption), tight RBAC on `secrets` |
| OpenTofu state | Local file, encrypted | S3/GCS backend with `use_lockfile = true`, versioning, encryption via `aws_kms` or `openbao` key provider |
| OpenTofu runs | Your laptop | CI with OIDC, plan on PR, apply on main behind approval (see doc 09); or a TACOS (Spacelift, env0, Scalr, Atlantis) |
| Image tags | Version tags | Immutable digests or SHA tags; signed images (cosign) verified by an admission policy |
| Pod security | PSA `restricted` on app namespaces | Same, plus Kyverno or Gatekeeper policies (no `latest`, required limits, allowed registries) |
| Network | Open | NetworkPolicies default-deny per namespace; only ESO and OpenBao clients may reach OpenBao |
| Observability | `kubectl` | Prometheus + Grafana dashboards for Argo CD, ESO and OpenBao metrics; alerts on sync failures and ExternalSecret errors |

## Habits that matter more than tools

- **Git is the only way in.** `selfHeal: true` plus no human write RBAC in
  prod clusters. Emergency fixes go through a fast-tracked PR.
- **Small blast radius.** Separate OpenTofu state per layer and per
  environment; separate AppProjects per team.
- **Everything pinned.** Chart versions, image tags, provider versions, CLI
  versions. Upgrades are PRs you can revert.
- **No secret in Git, no secret in state.** ExternalSecret references in Git,
  values in OpenBao, ephemeral + write-only in OpenTofu.
- **Practice the bad day.** Restore OpenBao from a snapshot, rebuild a
  cluster from Git (`make down && make up` is the small version of this),
  rotate a leaked credential.

## Where this sits in the job market (late 2026)

What platform and DevOps job descriptions keep asking for, and how this lab
maps to it:

- **GitOps with Argo CD**: the dominant CD tool for Kubernetes. ApplicationSets,
  AppProjects/RBAC, multi-cluster, sync waves and hooks are the interview
  topics. Covered.
- **Terraform / OpenTofu**: IaC remains required. Module design, state
  management, CI with OIDC, and handling secrets in state come up most.
  Knowing both tools and their differences is a plus. Covered.
- **Secrets management**: Vault/OpenBao concepts (auth methods, policies,
  dynamic secrets, auto-unseal) plus External Secrets Operator. Covered,
  except dynamic DB secrets, which is the best next exercise.
- **Kubernetes security basics**: Pod Security Admission, least-privilege
  RBAC, NetworkPolicies, image signing. Partly covered.
- **Adjacent and growing**: Kargo or Argo Rollouts for progressive delivery,
  Crossplane for cloud resources from Kubernetes, Backstage for developer
  portals. Learn after this.

For your data platform work: KubeRay, the Spark operator and Flink operator
install exactly like OpenBao here (an Application with a Helm chart in the
`platform` project), and Ray clusters or Spark applications become app
overlays per environment, with their S3 or database credentials coming from
OpenBao through ExternalSecrets.

Next: [11 · Architecture diagram](11-architecture.md)
