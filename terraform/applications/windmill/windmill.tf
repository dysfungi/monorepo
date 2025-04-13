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
      hub = {
        baseDomain   = "windmill.frank.sh"
        baseProtocol = "https"
        affinity     = local.affinity
        resources    = local.resources
      }
      postgresql = {
        enabled = false
      }
      windmill = {
        appReplicas = 2
        lspReplicas = 2
        app = {
          replicas    = 2 # autoscaling-only: https://artifacthub.io/packages/helm/windmill/windmill?modal=template&template=autoscaling.yaml
          autoscaling = local.autoscaling
          affinity    = local.affinity
          resources   = local.resources
        }
        baseDomain            = "windmill.frank.sh"
        baseProtocol          = "https"
        cookieDomain          = "windmill.frank.sh"
        databaseUrlSecretName = kubernetes_secret.db.metadata[0].name
        databaseUrlSecretKey  = "appUrl"
        lsp = {
          replicas    = 2 # autoscaling-only: https://artifacthub.io/packages/helm/windmill/windmill?modal=template&template=autoscaling.yaml
          autoscaling = local.autoscaling
          affinity    = local.affinity
          resources   = local.resources
        }
        multiplayer = {
          affinity = local.affinity
        }
        postgres = {
          enabled = false
        }
        workerGroups = [
          {
            name     = "default"
            replicas = 3
            mode     = "worker"
            affinity = local.affinity
            podSecurityContext = {
              runAsUser    = 0
              runAsNonRoot = false
            }
            resources              = local.resources
            terminationGracePeriod = 300
          },
          {
            name                   = "native"
            replicas               = 2
            mode                   = "worker"
            terminationGracePeriod = 300
            affinity               = local.affinity
            podSecurityContext = {
              runAsUser    = 0
              runAsNonRoot = false
            }
            resources = local.resources
            extraEnv = [
              {
                name  = "NUM_WORKERS"
                value = "8"
              },
              {
                name  = "SLEEP_QUEUE"
                value = "200"
              }
            ]
          },
          {
            name                   = "gpu"
            replicas               = 0
            mode                   = "worker"
            terminationGracePeriod = 300
            affinity               = local.affinity
            podSecurityContext = {
              runAsUser    = 0
              runAsNonRoot = false
            }
            resources = local.resources
          },
        ]
      }
    }),
  ]
}
