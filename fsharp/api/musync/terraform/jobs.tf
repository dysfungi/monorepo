# One-shot migration Job: applies the Phase 1a concerts migrations (dbmate,
# containerized) against the module-provisioned musync_app database on every
# deploy. wait_for_completion gates the apply on a clean migration, mirroring
# fsharp/api/automate/terraform/jobs.tf.
resource "kubernetes_job" "dbmate" {
  metadata {
    name      = "musync-dbmigrate"
    namespace = local.namespace
    labels = merge(local.labels, {
      "app.kubernetes.io/instance" = "dbmigrate"
    })
  }

  spec {
    template {
      metadata {}

      spec {
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

        restart_policy = "Never"

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
