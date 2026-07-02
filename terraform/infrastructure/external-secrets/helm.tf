# External Secrets Operator. installCRDs lets the chart manage the
# external-secrets.io CRDs (including ClusterSecretStore, applied in
# cluster_secret_store.tf).
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.7.0"
  namespace  = local.namespace

  values = [
    yamlencode({
      installCRDs = true
      # Lean profile (see docs/right-sizing-resources.md). Per-component resources:
      # the top-level block is the controller (busiest -- reconciles every
      # ExternalSecret, so it carries the largest memory floor at 128Mi); webhook and
      # certController are lightweight admission/cert helpers. CPU limits omitted
      # fleet-wide; memory limit == request for the lightweight webhook/certController.
      resources = {
        requests = {
          cpu    = "10m"
          memory = "128Mi"
        }
        # Limit raised 128->160Mi for headroom: the controller runs at a steady
        # ~105Mi that climbs over uptime, and it is on the ESO critical path.
        limits = {
          memory = "160Mi"
        }
      }
      webhook = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "64Mi"
          }
          limits = {
            memory = "64Mi"
          }
        }
      }
      certController = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "64Mi"
          }
          limits = {
            memory = "64Mi"
          }
        }
      }
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
# pass neither connect.credentials nor connect.credentials_base64).
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
        # Lean profile (see docs/right-sizing-resources.md). The connect pod runs TWO
        # containers with SEPARATE resource keys -- this chart has no pod-level
        # connect.resources. connect-api serves ESO reads; connect-sync refreshes the
        # local cache. The pod-level target (64Mi req/lim) is split evenly across them.
        # CPU limits omitted fleet-wide.
        api = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              memory = "32Mi"
            }
          }
        }
        sync = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              memory = "32Mi"
            }
          }
        }
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
# change -- so pods pick up secrets that ESO rotates.
resource "helm_release" "reloader" {
  name       = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  version    = "2.2.12"
  namespace  = local.namespace

  # Lean profile (see docs/right-sizing-resources.md). The chart shipped no resources
  # by default, so this ADDS a declaration. Chart path is reloader.deployment.resources;
  # CPU limit omitted fleet-wide.
  values = [
    yamlencode({
      reloader = {
        deployment = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "96Mi"
            }
            limits = {
              memory = "96Mi"
            }
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.external_secrets]
}
