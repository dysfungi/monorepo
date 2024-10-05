resource "kubernetes_namespace" "kube_prometheus" {
  metadata {
    name = "kube-prometheus"
  }
}

# https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
resource "helm_release" "kube_prometheus" {
  name             = "kube-prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "62.7.0"
  namespace        = kubernetes_namespace.kube_prometheus.metadata[0].name
  create_namespace = false

  set {
    name  = "fullnameOverride"
    value = "kube-prometheus"
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  values = [
    yamlencode({
      "prometheus" = {
        "prometheusSpec" = {
          "ruleSelector" = {
            "matchLabels" = null
          }
          "serviceMonitorSelector" = {
            "matchLabels" = null
          }
          "podMonitorSelector" = {
            "matchLabels" = null
          }
          "probeSelector" = {
            "matchLabels" = null
          }
          "scrapeConfigSelector" = {
            "matchLabels" = null
          }
        }
      }
      "thanosRuler" = {
        "thanosRulerSpec" = {
          "ruleSelector" = {
            "matchLabels" = null
          }
        }
      }
    }),
  ]
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
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
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

# https://artifacthub.io/packages/helm/prometheus-community/prometheus-blackbox-exporter
# https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/README.md
resource "helm_release" "blackbox_exporter" {
  name             = "prometheus-blackbox-exporter"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-blackbox-exporter"
  version          = "9.0.0"
  namespace        = kubernetes_namespace.kube_prometheus.metadata[0].name
  create_namespace = false

  # https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/values.yaml#L272
  set {
    name  = "serviceMonitor.enabled"
    value = true
  }

  set {
    name  = "serviceMonitor.selfMonitor.enabled"
    value = true
  }

  values = [
    yamlencode({
      "serviceMonitor" = {
        "enabled" = true
        "selfMonitor" = {
          "enabled" = true
        }
        "targets" = [
          {
            "name"          = "frank.sh"
            "url"           = "http://frank.sh"
            "module"        = "http_2xx"
            "interval"      = "5s"
            "scrapeTimeout" = "5s"
          },
          {
            "name"          = "httpbin"
            "url"           = "http://httpbin.frank.sh/ip"
            "module"        = "http_2xx"
            "interval"      = "5s"
            "scrapeTimeout" = "5s"
          },
        ]
      }
    }),
    yamlencode({
      "prometheusRule" = {
        "enabled"   = false
        "namespace" = helm_release.kube_prometheus.namespace
        "rules"     = []
      }
    }),
  ]
}
