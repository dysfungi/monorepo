locals {
  monitoringNodeSelector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "monitoring"
  }
  probe_interval       = "15s"
  dashboard_synthetics = "https://grafana.frank.sh/d/adzyuodr7k6bka/synthetics"
  subannotation_value  = "  VALUE = {{ $value }}"
  subannotation_labels = "  LABEL = {{ $labels }}"
}

resource "kubernetes_namespace" "kube_prometheus" {
  metadata {
    name = "kube-prometheus"
  }
}

data "healthchecksio_channel" "email" {
  kind = "email"
}

resource "healthchecksio_check" "prom_watchdog" {
  name = "frankenstructure-prom-operator-watchdog"
  desc = "Prometheus Operator Watchdog for Frankenstructure"

  grace    = 360 # seconds
  schedule = "* * * * *"
  timezone = "America/Los_Angeles"
  channels = [
    data.healthchecksio_channel.email.id,
  ]
}

resource "kubernetes_secret" "prom_secrets" {
  metadata {
    name      = "prometheus-secrets"
    namespace = kubernetes_namespace.kube_prometheus.metadata[0].name
  }
  data = {
    discordWebhookAlerts  = var.discord_webhook_alerts
    healthchecksioPingUrl = healthchecksio_check.prom_watchdog.ping_url
  }
}

resource "kubernetes_secret" "alertmanager_env" {
  metadata {
    name      = "alertmanager-env"
    namespace = kubernetes_namespace.kube_prometheus.metadata[0].name
  }
  data = {
    SMTP_TOKEN = var.smtp_password
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
    name  = "prometheus.prometheusSpec.externalUrl"
    value = "https://prometheus.frank.sh"
  }

  set {
    name  = "annotations.firing_alerts"
    value = "https://grafana.frank.sh/alerting/list?search=state%3Afiring+type%3Aalerting&view=state"
  }

  set {
    name  = "additionalRuleAnnotations.firing_alerts"
    value = "https://grafana.frank.sh/alerting/list?search=state%3Afiring+type%3Aalerting&view=state"
  }

  set {
    name  = "coreDns.enabled"
    value = true
  }

  set {
    name = "kubeControllerManager.enabled"
    # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
    value = false
  }

  set {
    name  = "kubeDns.enabled"
    value = false # conflicts with coreDns
  }

  set {
    name  = "kubeEtcd.enabled"
    value = true
  }

  set {
    name = "kubeProxy.enabled"
    # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
    value = false
  }

  set {
    name = "kubeScheduler.enabled"
    # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
    value = false
  }

  set {
    name  = "kubeStateMetrics.enabled"
    value = true
  }

  set {
    name  = "kubelet.enabled"
    value = true
  }

  values = [
    yamlencode({
      "alertmanager" = {
        "alertmanagerSpec" = {
          # https://github.com/prometheus-operator/prometheus-operator/issues/3737#issuecomment-1326667523
          "alertmanagerConfigMatcherStrategy" = {
            "type" = "None"
          }
          # https://github.com/prometheus-operator/prometheus-operator/issues/6805#issuecomment-2273008543
          "containers" = [
            {
              "name" = "config-reloader"
              "envFrom" = [
                {
                  "secretRef" = {
                    "name"     = kubernetes_secret.alertmanager_env.metadata[0].name
                    "optional" = false
                  }
                },
              ]
            },
          ]
          "initContainers" = [
            {
              "name" = "init-config-reloader"
              "envFrom" = [
                {
                  "secretRef" = {
                    "name"     = kubernetes_secret.alertmanager_env.metadata[0].name
                    "optional" = false
                  }
                },
              ]
            },
          ]
          "nodeSelector" = local.monitoringNodeSelector
          "storage" = {
            "volumeClaimTemplate" = {
              "spec" = {
                "storageClassName" = "vultr-block-storage"
                "accessModes"      = ["ReadWriteOnce"]
                "resources" = {
                  "requests" = {
                    "storage" = "10Gi"
                  }
                }
              }
            }
          }
        }
        "config" = {
          "global" = {
            # https://prometheus.io/docs/alerting/latest/configuration/#file-layout-and-global-settings
            # https://proton.me/support/smtp-submission#setup
            # https://github.com/prometheus-operator/prometheus-operator/issues/6805#issuecomment-2273008543
            "smtp_from"          = var.smtp_username
            "smtp_smarthost"     = "${var.smtp_server}:${var.smtp_port}"
            "smtp_hello"         = "frank.sh"
            "smtp_auth_username" = var.smtp_username
            "smtp_auth_password" = "$(SMTP_TOKEN)"
            "smtp_auth_identity" = var.smtp_username
            "smtp_require_tls"   = true
          }
        }
      }
      "grafana" = {
        "persistence" = {
          "enabled" = true
          "type" : "pvc"
          "storageClassName" = "vultr-block-storage"
          "accessModes"      = ["ReadWriteOnce"]
          "size"             = "10Gi"
          "finalizers"       = ["kubernetes.io/pvc-protection"]
        }
      }
      "prometheus" = {
        "prometheusSpec" = {
          "nodeSelector" = local.monitoringNodeSelector
          "paused"       = false # https://prometheus-operator.dev/docs/platform/storage/#resizing-volumes
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
          # https://prometheus-operator.dev/docs/platform/storage/
          # https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.StorageSpec
          # https://docs.vultr.com/vultr-kubernetes-engine#features-of-the-managed-control-plane
          # https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack?modal=values&path=prometheus.prometheusSpec.storageSpec
          "storageSpec" = {
            "volumeClaimTemplate" = {
              "spec" = {
                "storageClassName" = "vultr-block-storage"
                "accessModes"      = ["ReadWriteOnce"]
                "resources" = {
                  "requests" = {
                    "storage" = "50Gi"
                  }
                }
              }
            }
          }
        }
      }
      "prometheusOperator" = {
        "admissionWebhooks" = {
          "deployment" = {
            "nodeSelector" = local.monitoringNodeSelector
          }
          "patch" = {
            "nodeSelector" = local.monitoringNodeSelector
          }
        }
        "nodeSelector" = local.monitoringNodeSelector
      }
      "thanosRuler" = {
        "thanosRulerSpec" = {
          "nodeSelector" = local.monitoringNodeSelector
          "ruleSelector" = {
            "matchLabels" = null
          }
          "storage" = {
            "volumeClaimTemplate" = {
              "spec" = {
                "storageClassName" = "vultr-block-storage"
                "accessModes"      = ["ReadWriteOnce"]
                "resources" = {
                  "requests" = {
                    "storage" = "10Gi"
                  }
                }
              }
            }
          }
        }
      }
    }),
  ]
}

resource "kubernetes_role" "kube_prom_operator_secret_reader" {
  metadata {
    name      = "${helm_release.kube_prometheus.name}-operator:secret-reader"
    namespace = helm_release.kube_prometheus.namespace
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    resource_names = [
      kubernetes_secret.prom_secrets.metadata[0].name,
      kubernetes_secret.alertmanager_env.metadata[0].name,
    ]
    verbs = ["get", "watch"]
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding
resource "kubernetes_role_binding" "kube_prom_secret_reader" {
  metadata {
    name      = kubernetes_role.kube_prom_operator_secret_reader.metadata[0].name
    namespace = kubernetes_role.kube_prom_operator_secret_reader.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.kube_prom_operator_secret_reader.metadata[0].name
  }
  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = "${helm_release.kube_prometheus.name}-operator"
    namespace = helm_release.kube_prometheus.namespace
  }
}

resource "kubernetes_manifest" "notifications" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1alpha1"
    "kind"       = "AlertmanagerConfig"
    "metadata" = {
      "name"      = "notifications"
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "route" = {
        "receiver" = "null"
        "groupBy" = [
          "alertname",
        ]
        "groupWait"      = "30s"
        "groupInterval"  = "5m"
        "repeatInterval" = "12h"
        "routes" = [
          {
            "receiver"       = "deadmans-switch"
            "groupWait"      = "0s"
            "groupInterval"  = "30s"
            "repeatInterval" = "30s"
            "matchers" = [
              {
                "name"      = "severity"
                "matchType" = "="
                "value"     = "heartbeat"
              },
            ]
          },
          {
            "receiver" = "low-priority"
            "matchers" = [
              {
                "name"      = "severity"
                "matchType" = "~="
                "value"     = "error|critical"
              },
            ]
          },
          {
            "receiver" = "low-priority"
            "matchers" = [
              {
                "name"      = "severity"
                "matchType" = "="
                "value"     = "warning"
              },
            ]
          },
        ]
      }
      "receivers" = [
        {
          "name" = "deadmans-switch"
          "webhookConfigs" = [
            {
              "sendResolved" = false
              "urlSecret" = {
                "key"      = "healthchecksioPingUrl"
                "name"     = kubernetes_secret.prom_secrets.metadata[0].name
                "optional" = false
              }
            },
          ]
        },
        {
          "name" = "low-priority"
          "discordConfigs" = [
            {
              "sendResolved" = true
              "apiURL" = {
                "key"      = "discordWebhookAlerts"
                "name"     = kubernetes_secret.prom_secrets.metadata[0].name
                "optional" = false
              }
            },
          ]
          "emailConfigs" = [
            # https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1alpha1.EmailConfig
            {
              "sendResolved" = true
              "to"           = "alerts@frank.sh"
            },
          ]
        },
        { "name" = "null" },
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
  values = [
    yamlencode({
      "nodeSelector" = local.monitoringNodeSelector
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
            "interval"      = local.probe_interval
            "scrapeTimeout" = local.probe_interval
          },
          {
            "name"          = "grafana"
            "url"           = "http://grafana.frank.sh"
            "module"        = "http_2xx"
            "interval"      = local.probe_interval
            "scrapeTimeout" = local.probe_interval
          },
          {
            "name"          = "httpbin"
            "url"           = "http://httpbin.frank.sh/ip"
            "module"        = "http_2xx"
            "interval"      = local.probe_interval
            "scrapeTimeout" = local.probe_interval
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

resource "kubernetes_manifest" "deadmans_switch_promrule" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "PrometheusRule"
    "metadata" = {
      "name"      = "deadmans-switch"
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "groups" = [
        {
          "name" = "deadmans-switch"
          "rules" = [
            {
              # https://github.com/gouthamve/deadman
              # https://blog.devops.dev/prometheus-dead-mans-switch-39cb221840b4
              "alert" = "DeadMansSwitch"
              "expr"  = "vector(1)"
              "labels" = {
                "severity" = "heartbeat"
              }
              "annotations" = {
                "summary" = "An alert that should always be firing to certify that Alertmanager is working properly."
                "description" = join("\n", [
                  "This is an alert meant to ensrue that the entire alerting pipeline",
                  " is functional. This alert is always firing; therefore, it should",
                  " always be firing in Alertmanager and always fire against a receiver.",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
              }
            },
          ]
        },
      ]
    }
  }
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
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
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

/*
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
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
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
*/

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

resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = helm_release.kube_prometheus.namespace
    labels = {
      "grafana_dashboard" = "1"
    }
  }
  data = {
    for filename in fileset("${path.module}/grafana-dashboards", "*.json") : filename => file("${path.module}/grafana-dashboards/${filename}")
  }
}
