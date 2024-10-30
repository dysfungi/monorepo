# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Probe
# https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/blackbox-exporter.md#complete-example

resource "kubernetes_manifest" "probe" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "Probe"
    "metadata" = {
      "name"      = "${helm_release.windmill.name}-probe"
      "namespace" = helm_release.windmill.namespace
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
            format("%s?token=%s", var.windmill_probe_url, var.windmill_probe_token),
          ]
          "relabelingConfigs" = [
            {
              "sourceLabels" = ["instance"]
              "targetLabel"  = "instance"
              "action"       = "replace"
              "replacement"  = var.windmill_probe_url
            },
            {
              "sourceLabels" = ["target"]
              "targetLabel"  = "target"
              "action"       = "replace"
              "replacement"  = "windmill"
            },
          ]
        }
      }
    }
  }
}
