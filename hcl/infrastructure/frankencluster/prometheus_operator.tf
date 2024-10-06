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

  set {
    name  = "alertmanager.alertmanagerSpec.externalUrl"
    value = "https://alertmanager.frank.sh"
  }

  set {
    name  = "annotations.firing_alerts"
    value = "https://grafana.frank.sh/alerting/list?search=state%3Afiring+type%3Aalerting&view=state"
  }

  set {
    name  = "additionalRuleAnnotations.firing_alerts"
    value = "https://grafana.frank.sh/alerting/list?search=state%3Afiring+type%3Aalerting&view=state"
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

locals {
  dashboard_synthetics = "https://grafana.frank.sh/d/adzyuodr7k6bka/synthetics"
  subannotation_value  = "  VALUE = {{ $value }}"
  subannotation_labels = "  LABEL = {{ $labels }}"
}

resource "kubernetes_manifest" "alerts" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "PrometheusRule"
    "metadata" = {
      "name"      = "alerts"
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "groups" = [
        {
          "name" = "HTTP"
          "rules" = [
            {
              "alert" = "BlackboxProbeHttpFailure"
              "expr"  = "probe_http_status_code <= 199 OR probe_http_status_code >= 400"
              "for"   = "10m"
              "labels" = {
                "severity" = "critical"
                "type"     = "http"
                "action"   = "page"
              }
              "annotations" = {
                "summary" = "HTTP failure (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "HTTP status code is not 200-399",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
                "dashboard" = local.dashboard_synthetics
              }
            },
            {
              "alert" = "BlackboxProbeSlowHttp"
              "expr"  = "avg_over_time(probe_http_duration_seconds[1m]) > 1"
              "for"   = "1m"
              "labels" = {
                "severity" = "warning"
                "type"     = "http"
                "action"   = "page"
              }
              "annotations" = {
                "summary" = "Slow HTTP (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "HTTP request took more than 1s",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
                "dashboard" = local.dashboard_synthetics
              }
            }
          ]
        },
        {
          "name" = "SSL"
          "rules" = [
            {
              # https://samber.github.io/awesome-prometheus-alerts/rules#rule-blackbox-1-4
              "alert" = "BlackboxProbeSslCertificateWillExpireSoon"
              "expr"  = "round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 7"
              "for"   = "10m"
              "labels" = {
                "severity" = "warning"
                "type"     = "ssl"
                "action"   = "page"
              }
              "annotations" = {
                "summary" = "SSL certificate will expire soon (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "SSL certificate expires in less than 1 week",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
                "dashboard" = local.dashboard_synthetics
              }
            },
            {
              # https://samber.github.io/awesome-prometheus-alerts/rules#rule-blackbox-1-6
              "alert" = "BlackboxProbeSslCertificateWillExpireSoon"
              "expr"  = "round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 2"
              "for"   = "10m"
              "labels" = {
                "severity" = "critical"
                "type"     = "ssl"
                "action"   = "page"
              }
              "annotations" = {
                "summary" = "SSL certificate will expire soon (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "SSL certificate expires in less than 2 days",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
                "dashboard" = local.dashboard_synthetics
              }
            },
            {
              # https://samber.github.io/awesome-prometheus-alerts/rules#rule-blackbox-1-7
              "alert" = "BlackboxProbeSslCertificateExpired"
              "expr"  = "round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 0"
              "for"   = "10m"
              "labels" = {
                "severity" = "critical"
                "type"     = "ssl"
                "action"   = "page"
              }
              "annotations" = {
                "summary" = "SSL certificate expired (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "SSL certificate has expired already",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
                "dashboard" = local.dashboard_synthetics
              }
            },
          ]
        },
      ]
    }
  }
}
