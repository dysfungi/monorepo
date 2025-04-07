resource "kubernetes_config_map_v1" "scripts" {
  metadata {
    name      = "${var.app_name}-postgres-scripts"
    namespace = var.kubernetes_namespace
  }
  data = {
    # https://www.postgresql.org/docs/16/sql-grant.html
    # https://www.postgresql.org/docs/16/sql-alterdefaultprivileges.html
    "initdb.sql" = <<-EOT
      GRANT ALL PRIVILEGES
        ON SCHEMA public
        TO ${local.app.username}
        ;

      GRANT ALL PRIVILEGES
        ON ALL TABLES IN SCHEMA public
        TO ${local.app.username}
        ;

      GRANT ALL PRIVILEGES
        ON DATABASE ${local.app.dbname}
        TO ${local.app.username}
        ;

      ALTER DEFAULT PRIVILEGES
        IN SCHEMA public
        GRANT ALL PRIVILEGES
        ON SCHEMAS
        TO ${local.app.username}
        ;

      ALTER DEFAULT PRIVILEGES
        IN SCHEMA public
        GRANT ALL PRIVILEGES
        ON TABLES
        TO ${local.app.username}
        ;
    EOT
  }
}
