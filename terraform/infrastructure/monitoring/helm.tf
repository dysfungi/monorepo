# https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
resource "helm_release" "kube_prometheus" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "70.4.2"
  namespace        = local.namespace
  create_namespace = false

  values = [
    yamlencode({
      crds = {
        enabled = true
        upgradeJob = {
          enabled        = true
          forceConflicts = false
          affinity       = local.affinity
        }
      }
      cleanPrometheusOperatorObjectNames = true
      annotations = {
        firing_alerts = "https://grafana.frank.sh/alerting/list?search=state%3Afiring+type%3Aalerting&view=state"
      }
      additionalRuleAnnotations = {
        firing_alerts = "https://grafana.frank.sh/alerting/list?search=state%3Afiring+type%3Aalerting&view=state"
      }
      defaultRules = {
        disabled = {
          # https://github.com/prometheus-community/helm-charts/blob/kube-prometheus-stack-66.3.1/charts/kube-prometheus-stack/templates/prometheus/rules-1.14/kubernetes-resources.yaml#L60
          # NOTE: Disable KubeMemoryOvercommit because I don't need to overprovision extra nodes for failover yet.
          KubeMemoryOvercommit = true
        }
      }
      customRules = {
        Watchdog = {
          severity = "heartbeat"
        }
      }
      coreDns = {
        enabled = true
      }
      kubeControllerManager = {
        # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
        enabled = false
      }
      kubeDns = {
        enabled = false # conflicts with coreDns
      }
      kubeEtcd = {
        enabled = true
      }
      kubeProxy = {
        # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
        enabled = false
      }
      kubeScheduler = {
        # https://github.com/prometheus-community/helm-charts/issues/3368#issuecomment-1563510980
        enabled = false
      }
      kubeStateMetrics = {
        enabled = true
      }
      kubelet = {
        enabled = true
      }
      nodeExporter = {
        enabled = true
        operatingSystems = {
          aix = {
            enabled = false
          }
          darwin = {
            enabled = false
          }
          linux = {
            enabled = true
          }
        }
      }
      alertmanager = {
        alertmanagerSpec = {
          externalUrl = "https://${local.alertmanager_hostname}"
          affinity    = local.affinity
          resources = {
            requests = {
              cpu    = "5m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "10m"
              memory = "128Mi"
            }
          }
          # https://github.com/prometheus-operator/prometheus-operator/issues/3737#issuecomment-1326667523
          alertmanagerConfigMatcherStrategy = {
            type = "None"
          }
          # https://github.com/prometheus-operator/prometheus-operator/issues/6805#issuecomment-2273008543
          containers = [
            {
              name = "config-reloader"
              envFrom = [
                {
                  secretRef = {
                    name     = kubernetes_secret.alertmanager_env.metadata[0].name
                    optional = false
                  }
                },
              ]
            },
          ]
          initContainers = [
            {
              name = "init-config-reloader"
              envFrom = [
                {
                  secretRef = {
                    name     = kubernetes_secret.alertmanager_env.metadata[0].name
                    optional = false
                  }
                },
              ]
            },
          ]
          storage = {
            volumeClaimTemplate = {
              spec = {
                # volumeName = "alertmanager"
                storageClassName = "vultr-block-storage"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
        config = {
          global = {
            # https://prometheus.io/docs/alerting/latest/configuration/#file-layout-and-global-settings
            # https://proton.me/support/smtp-submission#setup
            # https://github.com/prometheus-operator/prometheus-operator/issues/6805#issuecomment-2273008543
            smtp_from          = var.smtp_username
            smtp_smarthost     = "${var.smtp_server}:${var.smtp_port}"
            smtp_hello         = var.root_domain
            smtp_auth_username = var.smtp_username
            smtp_auth_password = "$(SMTP_TOKEN)"
            smtp_auth_identity = var.smtp_username
            smtp_require_tls   = true
          }
          # https://github.com/prometheus/alertmanager/blob/main/docs/notification_examples.md#defining-reusable-templates
          # TODO: templates = []
        }
      }
      grafana = {
        adminUser     = "admin"
        adminPassword = var.grafana_admin_password
        "grafana.ini" = {
          server = {
            # domain    = local.grafana_hostname
            # http_port = 443
            # protocol  = "https"
            root_url = "https://${local.grafana_hostname}/"
          }
        }
        affinity = local.affinity
        resources = {
          requests = {
            cpu    = "50m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "512Mi"
          }
        }
        persistence = {
          enabled = true
          type : "sts"
          storageClassName = "vultr-block-storage"
          accessModes      = ["ReadWriteOnce"]
          size             = "10Gi"
          finalizers       = ["kubernetes.io/pvc-protection"]
        }
        sidecar = {
          resources = {
            requests = {
              cpu    = "10m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "50m"
              memory = "256Mi"
            }
          }
          defaultDashboardsTimezone = "browser"
          defaultDashboardsInterval = "1m"
          dashboards = {
            annotations = {
              grafana_folder = "K8"
            }
            # https://github.com/grafana/helm-charts/issues/526#issuecomment-878534071
            folderAnnotation = "grafana_folder"
            provider = {
              foldersFromFilesStructure = true
            }
          }
        }
      }
      kube-state-metrcis = {
        resource = {
          requests = {
            cpu    = "5m"
            memory = "20Mi"
          }
          limits = {
            cpu    = "10m"
            memory = "32Mi"
          }
        }
      }
      prometheus = {
        prometheusSpec = {
          # https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api-reference/api.md#monitoring.coreos.com/v1.ByteSize
          externalUrl   = "https://${local.prometheus_hostname}"
          affinity      = local.affinity
          retention     = "7d"
          retentionSize = "40GiB"
          resources = {
            requests = {
              cpu    = "250m"
              memory = "768Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
          paused = false # https://prometheus-operator.dev/docs/platform/storage/#resizing-volumes
          ruleSelector = {
            matchLabels = null
          }
          serviceMonitorSelector = {
            matchLabels = null
          }
          podMonitorSelector = {
            matchLabels = null
          }
          probeSelector = {
            matchLabels = null
          }
          scrapeConfigSelector = {
            matchLabels = null
          }
          # https://prometheus-operator.dev/docs/platform/storage/
          # https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.StorageSpec
          # https://docs.vultr.com/vultr-kubernetes-engine#features-of-the-managed-control-plane
          # https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack?modal=values&path=prometheus.prometheusSpec.storageSpec
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                # volumeName = "prometheus"
                storageClassName = "vultr-block-storage"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "128Gi"
                  }
                }
              }
            }
          }
        }
      }
      prometheusOperator = {
        fullnameOverride = "prometheus-operator"
        admissionWebhooks = {
          deployment = {
            affinity = local.affinity
          }
          patch = {
            affinity = local.affinity
          }
        }
        affinity = local.affinity
        resources = {
          requests = {
            cpu    = "5m"
            memory = "32Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "64Mi"
          }
        }
      }
      prometheus-node-exporter = {
        resources = {
          requests = {
            cpu    = "50m"
            memory = "16Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "32Mi"
          }
        }
      }
      thanosRuler = {
        thanosRulerSpec = {
          affinity = local.affinity
          resources = {
            requests = {
              cpu    = "250m"
              memory = "400Mi"
            }
            limits = {
              cpu    = "400m"
              memory = "600Mi"
            }
          }
          ruleSelector = {
            matchLabels = null
          }
          storage = {
            volumeClaimTemplate = {
              spec = {
                # volumeName = "thanos-ruler"
                storageClassName = "vultr-block-storage"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
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

# https://artifacthub.io/packages/helm/prometheus-community/prometheus-blackbox-exporter
# https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/README.md
resource "helm_release" "blackbox_exporter" {
  name             = "prometheus-blackbox-exporter"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-blackbox-exporter"
  version          = "9.0.1"
  namespace        = local.namespace
  create_namespace = false

  # https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/values.yaml#L272
  values = [
    yamlencode({
      replicas     = 2
      affinity     = local.affinity
      secretConfig = true
      config = {
        # https://github.com/prometheus/blackbox_exporter/blob/master/example.yml
        # https://artifacthub.io/packages/helm/prometheus-community/prometheus-blackbox-exporter?modal=values&path=config.modules
        modules = {
          http_2xx_todo = {
            prober  = "http"
            timeout = "5s"
            http = {
              valid_http_versions = [
                "HTTP/1.1",
                "HTTP/2.0",
              ]
              follow_redirects      = true
              preferred_ip_protocol = "ip4"
              headers = {
                Authorization = "Bearer TODO"
              }
            }
          }
        }
      }
      resources = {
        requests = {
          cpu    = "10m"
          memory = "25Mi"
        }
        limits = {
          cpu    = "50m"
          memory = "50Mi"
        }
      }
      serviceMonitor = {
        enabled = true
        selfMonitor = {
          enabled = true
        }
      }
    }),
  ]
}

# https://artifacthub.io/packages/helm/prometheus-community/prometheus-postgres-exporter
resource "helm_release" "postgres_exporter" {
  name             = "prometheus-postgres-exporter"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-postgres-exporter"
  version          = "6.4.0"
  namespace        = local.namespace
  create_namespace = false

  # https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/values.yaml#L272
  values = [
    yamlencode({
      replicaCount = 2
      affinity     = local.affinity
      image = {
        // https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-postgres-exporter/Chart.yaml#L2
        tag = "v0.16.0"
      }
      serviceMonitor = {
        enabled   = true
        namespace = local.namespace
      }
      config = {
        datasource = {
          host = data.vultr_database.pg.host
          userSecret = {
            name = kubernetes_secret.pg_exporter.metadata[0].name
            key  = "pgUsername"
          }
          passwordSecret = {
            name = kubernetes_secret.pg_exporter.metadata[0].name
            key  = "pgPassword"
          }
          port        = tostring(data.vultr_database.pg.port)
          database    = data.vultr_database.pg.dbname
          sslmode     = "require"
          extraparams = ""
        }
      }
      resources = {
        requests = {
          cpu    = "5m"
          memory = "25Mi"
        }
        limits = {
          cpu    = "10m"
          memory = "50Mi"
        }
      }
    }),
  ]
}
