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
      # Lean profile (see docs/right-sizing-resources.md): a demo/echo service with a
      # negligible footprint. CPU limit dropped fleet-wide (throttling hurts latency).
      resources = {
        requests = {
          cpu    = "10m"
          memory = "32Mi"
        }
        limits = {
          memory = "32Mi"
        }
      }
    }),
  ]
}
