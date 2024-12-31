resource "kubernetes_job" "dbmate" {
  metadata {
    generate_name = "automate-api-dbmigrate"
    namespace     = kubernetes_namespace.automate.metadata[0].name
    labels        = local.dbmigrate_labels
  }

  spec {
    template {
      metadata {
        generate_name = "automate-api-dbmigrate"
        labels        = local.dbmigrate_labels
      }

      spec {
        active_deadline_seconds = 5 * 60
        node_selector           = local.node_selector

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
}
