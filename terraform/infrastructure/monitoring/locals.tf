locals {
  alertmanager_hostname = "${var.alertmanager_subdomain}.${var.root_domain}"
  alertmanager_probe    = "http://${local.alertmanager_hostname}"
  grafana_hostname      = "${var.grafana_subdomain}.${var.root_domain}"
  grafana_probe         = "http://${local.grafana_hostname}"
  nodeSelector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "monitoring"
  }
  probe_interval       = "15s"
  prometheus_hostname  = "${var.prometheus_subdomain}.${var.root_domain}"
  prometheus_probe     = "http://${local.prometheus_hostname}"
  dashboard_synthetics = "https://grafana.frank.sh/d/adzyuodr7k6bka/synthetics"
  subannotation_value  = "  VALUE = {{ $value }}"
  subannotation_labels = "  LABEL = {{ $labels }}"
}
