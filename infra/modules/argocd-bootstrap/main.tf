# Bootstraps Argo CD and hands control to Git.
#
# This is the "thin bootstrap" pattern: OpenTofu installs only what Argo CD
# needs to start (itself, Git credentials, one root Application). Everything
# after that is declared in Git and reconciled by Argo CD, including Argo CD's
# own upgrades (see gitops/root/platform/argocd.yaml).

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.namespace
  }
}

# Argo CD discovers repository credentials from Secrets carrying this label.
# Every field goes through data_wo (write-only), so the token reaches the
# cluster but is never written to OpenTofu state.
resource "kubernetes_secret_v1" "repo" {
  metadata {
    name      = "platform-repo"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data_wo = {
    type     = "git"
    url      = var.repo_url
    username = var.repo_username
    password = var.repo_password
  }
  data_wo_revision = var.repo_credentials_revision
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  values     = [var.values_yaml]

  wait    = true
  timeout = 600

  # After bootstrap, Argo CD owns this release (it syncs the same chart and
  # values from Git). If someone changes values in Git, Argo CD applies them;
  # OpenTofu should not fight it on the next plan.
  lifecycle {
    ignore_changes = [values, version]
  }
}

# The root of the app-of-apps tree, installed with the small argocd-apps chart
# so we do not need CRDs to exist at plan time (kubernetes_manifest would).
resource "helm_release" "root" {
  name       = "argocd-root"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.6"

  values = [yamlencode({
    projects = {
      # The root app gets its own tightly scoped project: it may only create
      # Argo CD objects (Applications, ApplicationSets, AppProjects) in the
      # argocd namespace, from this one repo. Locking down "default" is a
      # common hardening step; nothing here uses it.
      bootstrap = {
        namespace   = var.namespace
        description = "Only the root app-of-apps lives here."
        sourceRepos = [var.repo_url]
        destinations = [{
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }]
        clusterResourceWhitelist = [] # no cluster-scoped objects at all
        namespaceResourceWhitelist = [
          { group = "argoproj.io", kind = "Application" },
          { group = "argoproj.io", kind = "ApplicationSet" },
          { group = "argoproj.io", kind = "AppProject" },
        ]
      }
    }

    applications = {
      root = {
        namespace  = var.namespace
        project    = "bootstrap"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = var.root_path
          directory      = { recurse = true }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
          retry = {
            limit   = 10
            backoff = { duration = "10s", factor = 2, maxDuration = "3m" }
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd, kubernetes_secret_v1.repo]
}
