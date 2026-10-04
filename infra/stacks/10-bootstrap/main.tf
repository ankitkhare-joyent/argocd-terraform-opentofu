# Layer 10: everything the cluster needs before GitOps can take over.
#
#   1. "Secret zero" for OpenBao: the seal key and the first admin password.
#      Something has to exist before the secrets manager does; this is it.
#   2. Argo CD itself, plus the root Application that points at Git.
#
# After this apply, OpenTofu stops touching the cluster's workloads. Argo CD
# installs OpenBao, External Secrets and the apps from gitops/.

locals {
  gitops_dir = "${path.root}/../../../gitops"

  # Single source of truth for the Argo CD chart version: read it from the
  # self-managed Application in Git, so bootstrap and GitOps never disagree.
  argocd_app           = yamldecode(file("${local.gitops_dir}/root/platform/argocd.yaml"))
  argocd_chart_version = local.argocd_app.spec.sources[0].targetRevision
}

# ---------------------------------------------------------------------------
# Secret zero for OpenBao
# ---------------------------------------------------------------------------

# Ephemeral resources generate a value for this run only. Combined with the
# write-only data_wo attribute below, the secret goes straight into the
# cluster and is never persisted in OpenTofu state or plan files.
ephemeral "random_bytes" "openbao_seal_key" {
  length = 32 # AES-256
}

ephemeral "random_password" "openbao_admin" {
  length  = 32
  special = false
}

resource "kubernetes_namespace_v1" "openbao" {
  metadata {
    name = "openbao"
  }
}

# Stand-in for a cloud KMS key. OpenBao's "static" seal reads this key at
# startup to unseal itself automatically. In production you would use
# seal "awskms" (or gcpckms, azurekeyvault, transit) and this Secret would not
# exist at all: the key would never leave the KMS.
resource "kubernetes_secret_v1" "openbao_seal" {
  metadata {
    name      = "openbao-seal"
    namespace = kubernetes_namespace_v1.openbao.metadata[0].name
  }

  data_wo = {
    BAO_STATIC_UNSEAL_KEY = ephemeral.random_bytes.openbao_seal_key.base64
  }
  # Write-only values can't be compared, so OpenTofu only rewrites the Secret
  # when this number changes. Never bump it for the seal key on a live
  # OpenBao: rotation must go through previous_key in the seal config.
  data_wo_revision = 1
}

# Consumed once, on OpenBao's first start, by the declarative self-init in
# gitops/platform/openbao/values.yaml to create the tofu-admin user.
resource "kubernetes_secret_v1" "openbao_bootstrap_admin" {
  metadata {
    name      = "openbao-bootstrap-admin"
    namespace = kubernetes_namespace_v1.openbao.metadata[0].name
  }

  data_wo = {
    INITIAL_ADMIN_PASSWORD = ephemeral.random_password.openbao_admin.result
  }
  data_wo_revision = 1
}

# ---------------------------------------------------------------------------
# Argo CD and the hand-off to Git
# ---------------------------------------------------------------------------

module "argocd" {
  source = "../../modules/argocd-bootstrap"

  chart_version = local.argocd_chart_version
  values_yaml   = file("${local.gitops_dir}/platform/argocd/values.yaml")

  repo_url      = var.git_repo_url
  repo_username = var.git_username
  repo_password = var.git_token

  # The OpenBao secrets must exist before Argo CD starts syncing OpenBao.
  depends_on = [
    kubernetes_secret_v1.openbao_seal,
    kubernetes_secret_v1.openbao_bootstrap_admin,
  ]
}
