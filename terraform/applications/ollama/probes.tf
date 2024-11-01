
# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Probe
# https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/blackbox-exporter.md#complete-example

resource "kubernetes_manifest" "probes" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "Probe"
    "metadata" = {
      "name"      = helm_release.ollama.name
      "namespace" = helm_release.ollama.namespace
    }
    "spec" = {
      "jobName"  = "blackbox"
      "interval" = "60s"
      "module"   = "http_2xx"
      "prober" = {
        "url" : "prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115",
      }
      "targets" = {
        "staticConfig" = {
          "static" = [
            local.probeUrl,
          ]
          "relabelingConfigs" = [
            {
              "sourceLabels" = ["instance"]
              "targetLabel"  = "instance"
              "action"       = "replace"
              "replacement"  = local.probeUrl
            },
            {
              "sourceLabels" = ["target"]
              "targetLabel"  = "target"
              "action"       = "replace"
              "replacement"  = helm_release.ollama.name
            },
          ]
        }
      }
    }
  }
}
