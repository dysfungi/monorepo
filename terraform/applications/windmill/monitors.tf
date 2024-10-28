# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.ServiceMonitor
resource "kubernetes_manifest" "service_monitor" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "ServiceMonitor"
    "metadata" = {
      "name"      = helm_release.windmill.name
      "namespace" = helm_release.windmill.namespace
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
          helm_release.windmill.namespace,
        ]
      }
      "selector" = {
        "matchLabels" = {
          "app.kubernetes.io/name" = "${helm_release.windmill.name}-app"
          "operated-prometheus"    = "true"
        }
      }
    }
  }
}
