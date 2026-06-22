resource "kubernetes_config_map" "general_grafana_dashboards" {
  metadata {
    name      = "general-grafana-dashboards"
    namespace = helm_release.kube_prometheus.namespace
    labels = {
      grafana_dashboard = "1"
    }
    annotations = {
      # grafana_folder = ""
    }
  }
  data = {
    for filename in fileset("${path.module}/grafana-dashboards", "*.json")
    : filename => file("${path.module}/grafana-dashboards/${filename}")
  }
}

resource "kubernetes_config_map" "folder_grafana_dashboards" {
  for_each = toset([
    for filename in fileset("${path.module}/grafana-dashboards", "**/*.json") : dirname(filename)
  ])

  metadata {
    name      = "${lower(each.key)}-grafana-dashboards"
    namespace = helm_release.kube_prometheus.namespace
    labels = {
      grafana_dashboard = "1"
    }
    annotations = {
      grafana_folder = each.key
    }
  }
  data = {
    for filename in fileset("${path.module}/grafana-dashboards/${each.key}", "*.json")
    : filename => file("${path.module}/grafana-dashboards/${each.key}/${filename}")
  }
}
