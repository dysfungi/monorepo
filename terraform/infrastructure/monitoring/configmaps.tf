resource "kubernetes_config_map" "general_grafana_dashboards" {
  metadata {
    name      = "general-grafana-dashboards"
    namespace = helm_release.kube_prometheus.namespace
    labels = {
      "grafana_dashboard" = "1"
    }
    annotations = {
      # "grafana_folder" = ""
    }
  }
  data = {
    for filename in fileset("${path.module}/grafana-dashboards", "*.json") :
    filename => file("${path.module}/grafana-dashboards/${filename}")
  }
}

resource "kubernetes_config_map" "blackbox_grafana_dashboards" {
  metadata {
    name      = "blackbox-grafana-dashboards"
    namespace = helm_release.kube_prometheus.namespace
    labels = {
      "grafana_dashboard" = "1"
    }
    annotations = {
      "grafana_folder" = "BB"
    }
  }
  data = {
    for filename in fileset("${path.module}/grafana-dashboards/BB", "*.json") :
    filename => file("${path.module}/grafana-dashboards/BB/${filename}")
  }
}

resource "kubernetes_config_map" "database_grafana_dashboards" {
  metadata {
    name      = "database-grafana-dashboards"
    namespace = helm_release.kube_prometheus.namespace
    labels = {
      "grafana_dashboard" = "1"
    }
    annotations = {
      "grafana_folder" = "DB"
    }
  }
  data = {
    for filename in fileset("${path.module}/grafana-dashboards/DB", "*.json") :
    filename => file("${path.module}/grafana-dashboards/DB/${filename}")
  }
}

resource "kubernetes_config_map" "gateway_grafana_dashboards" {
  metadata {
    name      = "gateway-grafana-dashboards"
    namespace = helm_release.kube_prometheus.namespace
    labels = {
      "grafana_dashboard" = "1"
    }
    annotations = {
      "grafana_folder" = "GW"
    }
  }
  data = {
    for filename in fileset("${path.module}/grafana-dashboards/GW", "*.json") :
    filename => file("${path.module}/grafana-dashboards/GW/${filename}")
  }
}
