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
      "secretConfig" = true
      "config" = {
        # https://github.com/prometheus/blackbox_exporter/blob/master/example.yml
        # https://artifacthub.io/packages/helm/prometheus-community/prometheus-blackbox-exporter?modal=values&path=config.modules
        "modules" = {
          "http_2xx_todo" = {
            "prober"  = "http"
            "timeout" = "5s"
            "http" = {
              "valid_http_versions" = [
                "HTTP/1.1",
                "HTTP/2.0",
              ]
              "follow_redirects"      = true
              "preferred_ip_protocol" = "ip4"
              "headers" = {
                "Authorization" = "Bearer TODO"
              }
            }
          }
        }
      }
      "serviceMonitor" = {
        "enabled" = true
        "selfMonitor" = {
          "enabled" = true
        }
      }
    }),
  ]
}
