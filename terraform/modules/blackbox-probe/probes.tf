# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Probe
# https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/blackbox-exporter.md#complete-example

resource "kubernetes_manifest" "probes" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "Probe"
    "metadata" = {
      "name"      = var.probe_name
      "namespace" = var.kubernetes_namespace
    }
    "spec" = {
      "jobName"  = "blackbox"
      "interval" = var.probe_interval
      "module"   = "http_2xx"
      "prober" = {
        "url" : "prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115",
      }
      "targets" = {
        "staticConfig" = {
          "static" = [
            var.probe_url,
          ]
          "relabelingConfigs" = [
            {
              "sourceLabels" = ["instance"]
              "targetLabel"  = "instance"
              "action"       = "replace"
              "replacement"  = var.probe_url
            },
            {
              "sourceLabels" = ["target"]
              "targetLabel"  = "target"
              "action"       = "replace"
              "replacement"  = var.probe_name
            },
          ]
        }
      }
    }
  }
}
