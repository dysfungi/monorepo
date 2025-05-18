resource "helm_release" "httpbin" {
  name       = "httpbin"
  repository = "https://matheusfm.dev/charts"
  chart      = "httpbin"
  version    = "0.1.1"
  namespace  = local.namespace

  values = [
    yamlencode({
      replicaCount = "2"
      podAnnotations = {
        "instrumentation.opentelemetry.io/inject-go" = "observability/opentelemetry-kube-stack"
        # Go Requires an additional annotation to the path of the binary on the container
        # https://github.com/mccutchen/go-httpbin/blob/main/Dockerfile#L16
        "instrumentation.opentelemetry.io/otel-go-auto-target-exe" = "/bin/go-httpbin"
      }
      autoscaling = {
        # TODO(dfrank): no matches for kind "HorizontalPodAutoscaler" in version "autoscaling/v2beta1"
        enabled                        = false
        minReplicas                    = 2
        maxReplicas                    = 8
        targetCPUUtilizationPercentage = 80
        # targetMemoryUtilizationPercentage = 80
      }
      affinity = {
        # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
        nodeAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 2
              preference = {
                matchExpressions = [
                  {
                    key      = "vke.vultr.com/node-pool"
                    operator = "In"
                    values = [
                      "default",
                    ]
                  },
                ]
              }
            },
          ]
        }
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
