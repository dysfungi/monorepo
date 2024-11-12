# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.PodMonitor
resource "kubernetes_manifest" "api_pod_monitor" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "PodMonitor"
    "metadata" = {
      "name"      = kubernetes_deployment.api.metadata[0].name
      "namespace" = kubernetes_namespace.automate.metadata[0].name
    }
    "spec" = {
      "podTargetLabels" = [
        "app.kubernetes.io/instance",
        "app.kubernetes.io/name",
        "pod-template-hash",
      ]
      "podMetricsEndpoints" = [
        {
          "port" = "metrics"
          // https://github.com/dotnet/dotnet-monitor/blob/main/documentation/configuration/metrics-configuration.md#customize-collection-interval-and-counts
          "interval" = "15s"
        },
      ]
      "namespaceSelector" = {
        "any" = false
        "matchNames" = [
          kubernetes_namespace.automate.metadata[0].name
        ]
      }
      "selector" = {
        "matchLabels" = {
          "app.kubernetes.io/instance" = kubernetes_deployment.api.metadata[0].labels["app.kubernetes.io/instance"]
          "app.kubernetes.io/name"     = kubernetes_deployment.api.metadata[0].labels["app.kubernetes.io/name"]
        }
      }
    }
  }
}
