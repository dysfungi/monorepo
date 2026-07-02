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
      # Node-loss resilience (see terraform/applications/README.md): keep the two
      # replicas on distinct nodes so losing a single node cannot take httpbin fully
      # offline. The matheusfm/httpbin chart does NOT expose
      # topologySpreadConstraints, so we express the intent with a soft (preferred)
      # podAntiAffinity on the hostname topology — never required, so a cluster with
      # only one schedulable node still runs both replicas.
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                topologyKey = "kubernetes.io/hostname"
                labelSelector = {
                  matchLabels = {
                    "app.kubernetes.io/name"     = "httpbin"
                    "app.kubernetes.io/instance" = "httpbin"
                  }
                }
              }
            },
          ]
        }
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
