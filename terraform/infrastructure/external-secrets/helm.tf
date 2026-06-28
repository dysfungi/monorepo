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

# 1Password Connect: serves vault items from an in-cluster cache so ESO's reads
# hit a local server instead of the rate-limited 1Password cloud SDK path. Only
# the Connect server (connect-api + connect-sync) is deployed; the 1Password
# Kubernetes operator is disabled (operator.create=false) because ESO -- not the
# OP operator -- reconciles secrets here. The pre-created credentials secret is
# referenced via connect.credentialsName (the chart does NOT manage it because we
# pass neither connect.credentials nor connect.credentials_base64). Chart affinity
# nests under connect.affinity (no top-level affinity key, unlike the ESO chart).
# Service: onepassword-connect:8080 (api) -- matches cluster_secret_store.yaml's
# connectHost.
resource "helm_release" "onepassword_connect" {
  name       = "onepassword-connect"
  repository = "https://1password.github.io/connect-helm-charts"
  chart      = "connect"
  version    = "2.4.1"
  namespace  = local.namespace

  values = [
    yamlencode({
      connect = {
        credentialsName = kubernetes_secret.onepassword_connect_credentials.metadata[0].name
        credentialsKey  = "1password-credentials.json"
        affinity        = local.affinity
      }
      operator = {
        create = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.external_secrets,
    kubernetes_secret.onepassword_connect_credentials,
  ]
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
