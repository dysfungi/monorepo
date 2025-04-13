# https://docs.nginx.com/nginx-gateway-fabric/how-to/monitoring/prometheus/#available-metrics-in-nginx-gateway-fabric
# https://github.com/nginx/nginx-prometheus-exporter#exported-metrics
# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.PodMonitor
resource "kubernetes_manifest" "gateway_pod_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = helm_release.gateway.name
      namespace = local.namespace
    }
    spec = {
      podTargetLabels = [
        "app.kubernetes.io/instance",
        "app.kubernetes.io/name",
        "pod-template-hash",
      ]
      podMetricsEndpoints = [
        {
          port = "metrics"
        },
      ]
      namespaceSelector = {
        any = false
        matchNames = [
          local.namespace,
        ]
      }
      selector = {
        matchLabels = {
          "app.kubernetes.io/instance" = helm_release.gateway.name
          "app.kubernetes.io/name"     = "nginx-gateway-fabric"
        }
      }
    }
  }
}
