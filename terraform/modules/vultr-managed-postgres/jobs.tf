resource "kubernetes_job_v1" "initdb_scripts" {
  metadata {
    name      = "${var.app_name}-initdb-scripts"
    namespace = var.kubernetes_namespace
  }
  spec {
    template {
      metadata {}
      spec {
        container {
          name  = "psql"
          image = "alpine/psql"
          command = [
            "psql",
            "--echo-all",
            "--file=/dbscripts/initdb.sql",
            "$(ADMIN_URL)",
          ]
          env_from {
            secret_ref {
              name     = one(kubernetes_secret.db.metadata).name
              optional = false
            }
          }
          volume_mount {
            name       = "sql-scripts"
            mount_path = "/dbscripts"
          }
        }
        restart_policy = "Never"
        volume {
          name = "sql-scripts"
          config_map {
            name     = one(kubernetes_config_map_v1.scripts.metadata).name
            optional = false
          }
        }
      }
    }
    backoff_limit = 4
  }
  wait_for_completion = true
  timeouts {
    create = "2m"
    update = "2m"
    delete = "1m"
  }
}
