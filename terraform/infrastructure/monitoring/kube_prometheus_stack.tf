# https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
resource "helm_release" "kube_prometheus" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "65.5.0"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      "cleanPrometheusOperatorObjectNames" = true
      "annotations" = {
        "firing_alerts" = "https://grafana.frank.sh/alerting/list?search=state%3Afiring+type%3Aalerting&view=state"
      }
      "additionalRuleAnnotations" = {
        "firing_alerts" = "https://grafana.frank.sh/alerting/list?search=state%3Afiring+type%3Aalerting&view=state"
      }
      "customRules" = {
        "Watchdog" = {
          "severity" = "heartbeat"
        }
      }
      "coreDns" = { "enabled" = true }
      "kubeControllerManager" = {
        # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
        "enabled" = false
      }
      "kubeDns" = {
        "enabled" = false # conflicts with coreDns
      }
      "kubeEtcd" = {
        "enabled" = true
      }
      "kubeProxy" = {
        # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
        "enabled" = false
      }
      "kubeScheduler" = {
        # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
        "enabled" = false
      }
      "kubeStateMetrics" = {
        "enabled" = true
      }
      "kubelet" = {
        "enabled" = true
      }
      "alertmanager" = {
        "alertmanagerSpec" = {
          "externalUrl" = "https://${local.alertmanager_hostname}"
          "affinity"    = local.affinity
          "resources" = {
            "requests" = {
              "cpu"    = "0.1"
              "memory" = "400Mi"
            }
            "limits" = {
              "cpu"    = "0.3"
              "memory" = "500Mi"
            }
          }
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
          "storage" = {
            "volumeClaimTemplate" = {
              "spec" = {
                # "volumeName" = "alertmanager"
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
            "smtp_hello"         = var.root_domain
            "smtp_auth_username" = var.smtp_username
            "smtp_auth_password" = "$(SMTP_TOKEN)"
            "smtp_auth_identity" = var.smtp_username
            "smtp_require_tls"   = true
          }
          # https://github.com/prometheus/alertmanager/blob/main/docs/notification_examples.md#defining-reusable-templates
          # TODO: "templates" = []
        }
      }
      "grafana" = {
        "adminPassword" = var.grafana_admin_password
        "persistence" = {
          "enabled" = true
          "type" : "sts"
          "storageClassName" = "vultr-block-storage"
          "accessModes"      = ["ReadWriteOnce"]
          "size"             = "10Gi"
          "finalizers"       = ["kubernetes.io/pvc-protection"]
        }
        "sidecar" = {
          "dashboards" = {
            "annotations" = {
              "grafana_folder" = "K8"
            }
            # https://github.com/grafana/helm-charts/issues/526#issuecomment-878534071
            "folderAnnotation" = "grafana_folder"
            "provider" = {
              "foldersFromFilesStructure" = true
            }
          }
        }
      }
      "prometheus" = {
        "prometheusSpec" = {
          "externalUrl" = "https://${local.prometheus_hostname}"
          "affinity"    = local.affinity
          "resources" = {
            "requests" = {
              "cpu"    = "0.4"
              "memory" = "400Mi"
            }
            "limits" = {
              "cpu"    = "0.8"
              "memory" = "1Gi"
            }
          }
          "paused" = false # https://prometheus-operator.dev/docs/platform/storage/#resizing-volumes
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
                # "volumeName" = "prometheus"
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
        "fullnameOverride" = "prometheus-operator"
        "admissionWebhooks" = {
          "deployment" = {
            "affinity" = local.affinity
          }
          "patch" = {
            "affinity" = local.affinity
          }
        }
        "affinity" = local.affinity
        "resources" = {
          "limits" = {
            "cpu"    = "200m"
            "memory" = "200Mi"
          }
          "requests" = {
            "cpu"    = "100m"
            "memory" = "100Mi"
          }
        }
      }
      "thanosRuler" = {
        "thanosRulerSpec" = {
          "affinity" = local.affinity
          "resources" = {
            "requests" = {
              "cpu"    = "0.2"
              "memory" = "400Mi"
            }
            "limits" = {
              "cpu"    = "0.5"
              "memory" = "1Gi"
            }
          }
          "ruleSelector" = {
            "matchLabels" = null
          }
          "storage" = {
            "volumeClaimTemplate" = {
              "spec" = {
                # "volumeName" = "thanos-ruler"
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
