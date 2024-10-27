locals {
  nodeSelector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "monitoring"
  }
  probe_interval       = "15s"
  dashboard_synthetics = "https://grafana.frank.sh/d/adzyuodr7k6bka/synthetics"
  subannotation_value  = "  VALUE = {{ $value }}"
  subannotation_labels = "  LABEL = {{ $labels }}"
}
