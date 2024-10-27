# https://artifacthub.io/packages/helm/prometheus-community/prometheus-blackbox-exporter
# https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/README.md
resource "helm_release" "blackbox_exporter" {
  name             = "prometheus-blackbox-exporter"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-blackbox-exporter"
  version          = "9.0.1"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  # https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/values.yaml#L272
  values = [
    yamlencode({
      "nodeSelector" = local.nodeSelector
      "serviceMonitor" = {
        "enabled" = true
        "selfMonitor" = {
          "enabled" = true
        }
        "targets" = [
          {
            "name"          = "frank.sh"
            "url"           = "http://frank.sh"
            "module"        = "http_2xx"
            "interval"      = local.probe_interval
            "scrapeTimeout" = local.probe_interval
          },
          {
            "name"          = "grafana"
            "url"           = "http://grafana.frank.sh"
            "module"        = "http_2xx"
            "interval"      = local.probe_interval
            "scrapeTimeout" = local.probe_interval
          },
          {
            "name"          = "httpbin"
            "url"           = "http://httpbin.frank.sh/ip"
            "module"        = "http_2xx"
            "interval"      = local.probe_interval
            "scrapeTimeout" = local.probe_interval
          },
        ]
      }
    }),
  ]
}