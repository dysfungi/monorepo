# External Secrets Operator. installCRDs lets the chart manage the
# external-secrets.io CRDs (including ClusterSecretStore, applied in
# cluster_secret_store.tf). affinity is the top-level controller affinity key.
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.7.0"
  namespace  = local.namespace

  values = [
    yamlencode({
      installCRDs = true
      affinity    = local.affinity
    })
  ]

  depends_on = [kubernetes_namespace.external_secrets]
}

# Stakater Reloader: restarts workloads when their referenced Secrets/ConfigMaps
# change -- so pods pick up secrets that ESO rotates. The reloader chart nests
# pod affinity under reloader.deployment.affinity (no top-level affinity key).
resource "helm_release" "reloader" {
  name       = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  version    = "2.2.12"
  namespace  = local.namespace

  values = [
    yamlencode({
      reloader = {
        deployment = {
          affinity = local.affinity
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.external_secrets]
}
