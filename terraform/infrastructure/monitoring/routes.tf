resource "kubernetes_manifest" "alertmanager_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "alertmanager"
      namespace = helm_release.kube_prometheus.namespace
    }
    spec = {
      parentRefs = [
        {
          kind        = "Gateway"
          name        = "prod-web"
          namespace   = "gateway"
          sectionName = "https-wildcard.${var.root_domain}"
        },
      ]
      hostnames = [
        local.alertmanager_hostname,
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            },
          ]
          backendRefs = [
            {
              kind      = "Service"
              name      = "${helm_release.kube_prometheus.name}-alertmanager"
              namespace = helm_release.kube_prometheus.namespace
              port      = 9093
            },
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "prometheus_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "prometheus"
      namespace = helm_release.kube_prometheus.namespace
    }
    spec = {
      parentRefs = [
        {
          kind        = "Gateway"
          name        = "prod-web"
          namespace   = "gateway"
          sectionName = "https-wildcard.${var.root_domain}"
        }
      ]
      hostnames = [
        local.prometheus_hostname,
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              kind      = "Service"
              name      = "${helm_release.kube_prometheus.name}-prometheus"
              namespace = helm_release.kube_prometheus.namespace
              port      = 9090
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "grafana_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "grafana"
      namespace = helm_release.kube_prometheus.namespace
    }
    spec = {
      parentRefs = [
        {
          kind        = "Gateway"
          name        = "prod-web"
          namespace   = "gateway"
          sectionName = "https-wildcard.${var.root_domain}"
        }
      ]
      hostnames = [
        local.grafana_hostname,
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              kind      = "Service"
              name      = "${helm_release.kube_prometheus.name}-grafana"
              namespace = helm_release.kube_prometheus.namespace
              port      = 80
            }
          ]
        }
      ]
    }
  }
}
