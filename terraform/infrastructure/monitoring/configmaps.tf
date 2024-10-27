resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = helm_release.kube_prometheus.namespace
    labels = {
      "grafana_dashboard" = "1"
    }
  }
  data = {
    for filename in fileset("${path.module}/grafana-dashboards", "*.json") : filename => file("${path.module}/grafana-dashboards/${filename}")
  }
}
