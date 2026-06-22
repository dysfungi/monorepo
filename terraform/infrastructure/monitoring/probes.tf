# https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.Probe
# https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/blackbox-exporter.md#complete-example
module "alertmanager_probe" {
  source = "../../modules/blackbox-probe"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  probe_interval       = "30s"
  probe_name           = var.alertmanager_subdomain
  # https://grafana.com/docs/grafana/latest/developers/http_api/other/#health-api
  probe_url = "http://${module.alertmanager_route.primary_hostname}/-/ready"
}

module "grafana_probe" {
  source = "../../modules/blackbox-probe"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  probe_interval       = "30s"
  probe_name           = var.grafana_subdomain
  # https://prometheus.io/docs/alerting/latest/management_api/#readiness-check
  probe_url = "http://${module.grafana_route.primary_hostname}/api/health"
}

module "prometheus_probe" {
  source = "../../modules/blackbox-probe"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  probe_interval       = "30s"
  probe_name           = var.prometheus_subdomain
  # https://prometheus.io/docs/prometheus/latest/management_api/#readiness-check
  probe_url = "http://${module.prometheus_route.primary_hostname}/-/ready"
}
