resource "kubernetes_job" "dbmate" {
  metadata {
    name      = "automate-api-dbmigrate"
    namespace = local.namespace
    labels = merge(local.labels, {
      "app.kubernetes.io/instance" = "dbmigrate"
    })
  }

  spec {
    template {
      metadata {
      }

      spec {
        affinity {
          # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
          node_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 2
              preference {
                match_expressions {
                  key      = "vke.vultr.com/node-pool"
                  operator = "In"
                  values = [
                    "default",
                    local.namespace,
                  ]
                }
              }
            }
          }
        }
        node_selector = local.node_selector

        container {
          name  = "dbmate"
          image = "ghcr.io/amacneil/dbmate"
          args  = ["--wait", "up", "--strict", "--verbose"]

          env_from {
            secret_ref {
              name     = kubernetes_secret.dbmate.metadata[0].name
              optional = false
            }
          }

          volume_mount {
            mount_path = "/db/migrations"
            name       = "dbmigrations"
          }
        }

        volume {
          name = "dbmigrations"
          config_map {
            name     = kubernetes_config_map.dbmigrations.metadata[0].name
            optional = false

            dynamic "items" {
              for_each = kubernetes_config_map.dbmigrations.data

              content {
                key  = items.key
                path = items.key
              }
            }
          }
        }
      }
    }
  }

  wait_for_completion = true
  timeouts {
    create = "2m"
    delete = "2m"
    update = "2m"
  }
}
