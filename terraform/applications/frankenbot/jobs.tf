# Schema-migrate Job: runs dbmate against the frankenbot database to bring the
# work_state / budget_daily schema up to date, then completes. Mirrors automate's
# dbmate Job (same image, args, wait_for_completion, timeouts, ConfigMap-mounted
# migrations).
#
# Two adaptations vs automate, both noted deliberately:
#   1. Credentials come from the ADMIN dbmate secret (secrets.tf), not the app
#      secret — dbmate must CREATE tables and run the grant migration.
#   2. Node placement follows frankenbot's stack convention (REQUIRED
#      infrastructure node pool, same as the dispatcher) rather than automate's
#      pool names, which do not exist for this stack.
resource "kubernetes_job" "dbmate" {
  metadata {
    name      = "frankenbot-dbmigrate"
    namespace = local.namespace
    labels = merge(local.labels, {
      "app.kubernetes.io/instance" = "dbmigrate"
    })
  }

  spec {
    template {
      metadata {
        labels = local.labels
      }

      spec {
        node_selector = local.node_selector

        # REQUIRED: the migrate Job runs on the infrastructure node pool, same as
        # the dispatcher and the triage workers.
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = local.infra_nodepool_label_key
                  operator = "In"
                  values   = [local.infra_nodepool_label_value]
                }
              }
            }
          }
        }

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
