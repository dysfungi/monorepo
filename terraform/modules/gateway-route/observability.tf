# https://docs.nginx.com/nginx-gateway-fabric/how-to/monitoring/tracing/#create-the-observabilitypolicy
# https://docs.nginx.com/nginx-gateway-fabric/reference/api/#gateway.nginx.org%2fv1alpha2
resource "kubernetes_manifest" "general_observability_policy" {
  manifest = {
    apiVersion = "gateway.nginx.org/v1alpha2"
    kind       = "ObservabilityPolicy"
    metadata = {
      name      = kubernetes_manifest.route.manifest.metadata.name
      namespace = kubernetes_manifest.route.manifest.metadata.namespace
    }
    spec = {
      targetRefs = [
        {
          group = replace(kubernetes_manifest.route.manifest.apiVersion, "//.*$/", "")
          kind  = kubernetes_manifest.route.manifest.kind
          name  = kubernetes_manifest.route.manifest.metadata.name
        },
      ]
      tracing = {
        strategy = "ratio"
        ratio    = var.trace_sampling
        # spanName = ""
        # spanAttributes = [
        #   {},
        # ]
      }
    }
  }
}
