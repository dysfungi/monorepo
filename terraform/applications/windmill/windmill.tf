# https://www.windmill.dev/docs/advanced/self_host#helm-chart
# https://artifacthub.io/packages/helm/windmill/windmill
resource "helm_release" "windmill" {
  name       = "windmill"
  repository = "https://windmill-labs.github.io/windmill-helm-charts"
  chart      = "windmill"
  version    = "2.0.300"
  namespace  = kubernetes_namespace.windmill.metadata[0].name

  values = [
    yamlencode({
      "hub" = {
        "baseDomain"   = "windmill.frank.sh"
        "baseProtocol" = "https"
        "nodeSelector" = local.nodeSelector
        "resources" = {
          "limits" = {
            "cpu"    = "0.5"
            "memory" = "1Gi"
          }
        }
      }
      "postgresql" = {
        "enabled" = false
      }
      "windmill" = {
        "app" = {
          "nodeSelector" = local.nodeSelector
          "resources" = {
            "limits" = {
              "cpu"    = "1"
              "memory" = "1.5Gi"
            }
          }
        }
        "baseDomain"            = "windmill.frank.sh"
        "baseProtocol"          = "https"
        "cookieDomain"          = "windmill.frank.sh"
        "databaseUrlSecretName" = kubernetes_secret.db.metadata[0].name
        "databaseUrlSecretKey"  = "appUrl"
        "lsp" = {
          "nodeSelector" = local.nodeSelector
        }
        "multiplayer" = {
          "nodeSelector" = local.nodeSelector
        }
        "postgres" = {
          "enabled" = false
        }
        "workerGroups" = [
          {
            "name"         = "default"
            "replicas"     = 3
            "mode"         = "worker"
            "nodeSelector" = local.nodeSelector
            "podSecurityContext" = {
              "runAsUser"    = 0
              "runAsNonRoot" = false
            }
            "resources" = {
              "limits" = {
                "cpu"    = "1"
                "memory" = "1.5Gi"
              }
            }
            "terminationGracePeriod" = 300
          },
          {
            "name"         = "native"
            "replicas"     = 0
            "nodeSelector" = local.nodeSelector
          },
          {
            "name"         = "gpu"
            "replicas"     = 0
            "nodeSelector" = local.nodeSelector
          },
        ]
      }
    }),
  ]
}
