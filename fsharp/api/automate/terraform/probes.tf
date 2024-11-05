# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Probe
# https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/blackbox-exporter.md#complete-example
resource "kubernetes_manifest" "probes" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "Probe"
    "metadata" = {
      "name"      = "automate"
      "namespace" = kubernetes_namespace.automate.metadata[0].name
    }
    "spec" = {
      "jobName"  = "blackbox"
      "interval" = "15s"
      "module"   = "http_2xx"
      "prober" = {
        "url" : "prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115",
      }
      "targets" = {
        "staticConfig" = {
          "static" = [
            local.probe,
          ]
          "relabelingConfigs" = [
            {
              "sourceLabels" = ["instance"]
              "targetLabel"  = "instance"
              "action"       = "replace"
              "replacement"  = local.probe
            },
            {
              "sourceLabels" = ["target"]
              "targetLabel"  = "target"
              "action"       = "replace"
              "replacement"  = kubernetes_namespace.automate.metadata[0].name
            },
          ]
        }
      }
    }
  }
}
