locals {
  alertmanager_hostname = "${var.alertmanager_subdomain}.${var.root_domain}"
  alertmanager_probe    = "http://${local.alertmanager_hostname}"
  grafana_hostname      = "${var.grafana_subdomain}.${var.root_domain}"
  grafana_probe         = "http://${local.grafana_hostname}"
  affinity = {
    # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
    nodeAffinity = {
      preferredDuringSchedulingIgnoredDuringExecution = [
        {
          weight = 2
          preference = {
            matchExpressions = [
              {
                key      = "vke.vultr.com/node-pool"
                operator = "In"
                values = [
                  "infrastructure",
                  kubernetes_namespace.monitoring.metadata[0].name,
                ]
              },
            ]
          }
        },
      ]
    }
  }
  probe_interval       = "15s"
  prometheus_hostname  = "${var.prometheus_subdomain}.${var.root_domain}"
  prometheus_probe     = "http://${local.prometheus_hostname}"
  subannotation_value  = "  VALUE = {{ $value }}"
  subannotation_labels = "  LABEL = {{ $labels }}"
}
