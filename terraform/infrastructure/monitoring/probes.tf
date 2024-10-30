# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Probe
# https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/blackbox-exporter.md#complete-example
resource "kubernetes_manifest" "alertmanager_probe" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "Probe"
    "metadata" = {
      "name"      = var.alertmanager_subdomain
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "jobName"  = "blackbox"
      "interval" = "30s"
      "module"   = "http_2xx"
      "prober" = {
        "url" : "prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115",
      }
      "targets" = {
        "staticConfig" = {
          "static" = [
            local.alertmanager_probe,
          ]
          "relabelingConfigs" = [
            {
              "sourceLabels" = ["instance"]
              "targetLabel"  = "instance"
              "action"       = "replace"
              "replacement"  = local.alertmanager_probe
            },
            {
              "sourceLabels" = ["target"]
              "targetLabel"  = "target"
              "action"       = "replace"
              "replacement"  = var.alertmanager_subdomain
            },
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "grafana_probe" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "Probe"
    "metadata" = {
      "name"      = var.grafana_subdomain
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "jobName"  = "blackbox"
      "interval" = "30s"
      "module"   = "http_2xx"
      "prober" = {
        "url" : "prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115",
      }
      "targets" = {
        "staticConfig" = {
          "static" = [
            local.grafana_probe,
          ]
          "relabelingConfigs" = [
            {
              "sourceLabels" = ["instance"]
              "targetLabel"  = "instance"
              "action"       = "replace"
              "replacement"  = local.grafana_probe
            },
            {
              "sourceLabels" = ["target"]
              "targetLabel"  = "target"
              "action"       = "replace"
              "replacement"  = var.grafana_subdomain
            },
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "prometheus_probe" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "Probe"
    "metadata" = {
      "name"      = var.prometheus_subdomain
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "jobName"  = "blackbox"
      "interval" = "30s"
      "module"   = "http_2xx"
      "prober" = {
        "url" : "prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115",
      }
      "targets" = {
        "staticConfig" = {
          "static" = [
            local.prometheus_probe,
          ]
          "relabelingConfigs" = [
            {
              "sourceLabels" = ["instance"]
              "targetLabel"  = "instance"
              "action"       = "replace"
              "replacement"  = local.prometheus_probe
            },
            {
              "sourceLabels" = ["target"]
              "targetLabel"  = "target"
              "action"       = "replace"
              "replacement"  = var.prometheus_subdomain
            },
          ]
        }
      }
    }
  }
}
