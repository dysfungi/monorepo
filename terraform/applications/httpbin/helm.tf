resource "helm_release" "httpbin" {
  name       = "httpbin"
  repository = "https://matheusfm.dev/charts"
  chart      = "httpbin"
  version    = "0.1.1"
  namespace  = local.namespace

  values = [
    yamlencode({
      replicaCount = "2"
      autoscaling = {
        # TODO(dfrank): no matches for kind "HorizontalPodAutoscaler" in version "autoscaling/v2beta1"
        enabled                        = false
        minReplicas                    = 2
        maxReplicas                    = 8
        targetCPUUtilizationPercentage = 80
        # targetMemoryUtilizationPercentage = 80
      }
      nodeSelector = {
        "kubernetes.io/os"        = "linux"
        "vke.vultr.com/node-pool" = "default"
      }
      resources = {
        requests = {
          cpu    = "10m"
          memory = "16Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    }),
  ]
}
