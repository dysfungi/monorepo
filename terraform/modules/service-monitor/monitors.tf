# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.ServiceMonitor
resource "kubernetes_manifest" "service_monitor" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "ServiceMonitor"
    "metadata" = {
      "name"      = var.service_name
      "namespace" = var.kubernetes_namespace
    }
    "spec" = {
      "targetLabels" = [
        "app.kubernetes.io/name",
      ]
      "podTargetLabels" = [
        "app.kubernetes.io/name",
        "pod-template-hash"
      ]
      "endpoints" = [
        {
          "port" = "metrics"
        },
      ]
      "namespaceSelector" = {
        "any" = false
        "matchNames" = [
          var.kubernetes_namespace,
        ]
      }
      "selector" = {
        "matchLabels" = {
          "app.kubernetes.io/name" = var.app_name
          "operated-prometheus"    = "true"
        }
      }
    }
  }
}
