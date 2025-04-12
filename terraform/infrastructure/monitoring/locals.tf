locals {
  namespace             = kubernetes_namespace.monitoring.metadata[0].name
  alertmanager_hostname = "${var.alertmanager_subdomain}.${var.root_domain}"
  grafana_hostname      = "${var.grafana_subdomain}.${var.root_domain}"
  prometheus_hostname   = "${var.prometheus_subdomain}.${var.root_domain}"
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
  subannotation_value  = "  VALUE = {{ $value }}"
  subannotation_labels = "  LABEL = {{ $labels }}"
}
