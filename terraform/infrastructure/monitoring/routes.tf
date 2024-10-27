resource "kubernetes_manifest" "alertmanager_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "alertmanager"
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = "prod-web"
          "namespace"   = "gateway"
          "sectionName" = "https-wildcard.frank.sh"
        }
      ]
      "hostnames" = [
        "alertmanager.frank.sh",
      ]
      "rules" = [
        {
          "matches" = [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/"
              }
            }
          ]
          "backendRefs" = [
            {
              "kind"      = "Service"
              "name"      = "${helm_release.kube_prometheus.name}-alertmanager"
              "namespace" = helm_release.kube_prometheus.namespace
              "port"      = 9093
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "prometheus_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "prometheus"
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = "prod-web"
          "namespace"   = "gateway"
          "sectionName" = "https-wildcard.frank.sh"
        }
      ]
      "hostnames" = [
        "prometheus.frank.sh",
      ]
      "rules" = [
        {
          "matches" = [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/"
              }
            }
          ]
          "backendRefs" = [
            {
              "kind"      = "Service"
              "name"      = "${helm_release.kube_prometheus.name}-prometheus"
              "namespace" = helm_release.kube_prometheus.namespace
              "port"      = 9090
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "grafana_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "grafana"
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = "prod-web"
          "namespace"   = "gateway"
          "sectionName" = "https-wildcard.frank.sh"
        }
      ]
      "hostnames" = [
        "grafana.frank.sh",
      ]
      "rules" = [
        {
          "matches" = [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/"
              }
            }
          ]
          "backendRefs" = [
            {
              "kind"      = "Service"
              "name"      = "${helm_release.kube_prometheus.name}-grafana"
              "namespace" = helm_release.kube_prometheus.namespace
              "port"      = 80
            }
          ]
        }
      ]
    }
  }
}
