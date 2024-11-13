# https://artifacthub.io/packages/helm/prometheus-community/prometheus-blackbox-exporter
# https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/README.md
resource "helm_release" "blackbox_exporter" {
  name             = "prometheus-blackbox-exporter"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-blackbox-exporter"
  version          = "9.0.1"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  # https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/values.yaml#L272
  values = [
    yamlencode({
      "replicas"     = 2
      "affinity"     = local.affinity
      "secretConfig" = true
      "config" = {
        # https://github.com/prometheus/blackbox_exporter/blob/master/example.yml
        # https://artifacthub.io/packages/helm/prometheus-community/prometheus-blackbox-exporter?modal=values&path=config.modules
        "modules" = {
          "http_2xx_todo" = {
            "prober"  = "http"
            "timeout" = "5s"
            "http" = {
              "valid_http_versions" = [
                "HTTP/1.1",
                "HTTP/2.0",
              ]
              "follow_redirects"      = true
              "preferred_ip_protocol" = "ip4"
              "headers" = {
                "Authorization" = "Bearer TODO"
              }
            }
          }
        }
      }
      "resources" = {
        "requests" = {
          "cpu"    = "0.1"
          "memory" = "50Mi"
        }
        "limits" = {
          "cpu"    = "0.2"
          "memory" = "300Mi"
        }
      }
      "serviceMonitor" = {
        "enabled" = true
        "selfMonitor" = {
          "enabled" = true
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
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  # https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/values.yaml#L272
  values = [
    yamlencode({
      "replicaCount" = 2
      "affinity"     = local.affinity
      "image" = {
        // https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-postgres-exporter/Chart.yaml#L2
        "tag" = "v0.16.0"
      }
      "serviceMonitor" = {
        "enabled"   = true
        "namespace" = kubernetes_namespace.monitoring.metadata[0].name
      }
      "config" = {
        "datasource" = {
          "host" = data.vultr_database.pg.host
          "userSecret" = {
            "name" = kubernetes_secret.pg_exporter.metadata[0].name
            "key"  = "pgUsername"
          }
          "passwordSecret" = {
            "name" = kubernetes_secret.pg_exporter.metadata[0].name
            "key"  = "pgPassword"
          }
          "port"        = tostring(data.vultr_database.pg.port)
          "database"    = data.vultr_database.pg.dbname
          "sslmode"     = "require"
          "extraparams" = ""
        }
      }
      "resources" = {
        "requests" = {
          "cpu"    = "0.1"
          "memory" = "50Mi"
        }
        "limits" = {
          "cpu"    = "0.2"
          "memory" = "300Mi"
        }
      }
    }),
  ]
}
