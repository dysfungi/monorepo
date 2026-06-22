module "alertmanager_route" {
  source = "../../modules/gateway-route"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  service_name         = "${helm_release.kube_prometheus.name}-alertmanager"
  service_port         = 9093
  subdomain            = var.alertmanager_subdomain
}

module "prometheus_route" {
  source = "../../modules/gateway-route"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  service_name         = "${helm_release.kube_prometheus.name}-prometheus"
  service_port         = 9090
  subdomain            = var.prometheus_subdomain
}

module "grafana_route" {
  source = "../../modules/gateway-route"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  service_name         = "${helm_release.kube_prometheus.name}-grafana"
  service_port         = 80
  subdomain            = var.grafana_subdomain
}
