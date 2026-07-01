resource "kubernetes_secret" "cr" {
  // https://docs.vultr.com/how-to-use-vultr-container-registry-with-kubernetes#generate-the-vultr-container-registry-kubernetes-credentials
  metadata {
    name      = "vultr-cr-credentials"
    namespace = local.namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.dockerconfigjson
  }
}

# The dispatcher's application DB connection: DATABASE_URL as the least-privilege
# frankenbot login role against the frankenbot database. Attached to the
# dispatcher via envFrom (cronjob_dispatcher.tf). Workers do NOT receive it.
# Mirrors automate's DB-URL secret shape.
resource "kubernetes_secret" "db" {
  metadata {
    name      = "frankenbot-db"
    namespace = local.namespace
    labels    = local.labels
  }
  data = {
    DATABASE_URL = join("", [
      "postgres:",
      "//${vultr_database_user.frankenbot.username}:${random_password.frankenbot_db.result}",
      "@${data.vultr_database.pg.host}:${data.vultr_database.pg.port}",
      "/${vultr_database_db.frankenbot.name}",
      "?sslmode=${local.dbsslmode}",
    ])
  }
}

# dbmate migration credentials. dbmate CREATEs tables and runs the grant
# migration, which the least-privilege frankenbot role cannot do on a locked-down
# PG public schema — so, exactly like automate's `automate-dbmate` secret, this
# uses the managed instance's ADMIN role. Consumed only by the schema-migrate Job
# (jobs.tf), never mounted on any long-lived workload.
resource "kubernetes_secret" "dbmate" {
  metadata {
    name      = "frankenbot-dbmate"
    namespace = local.namespace
    labels    = local.labels
  }
  data = {
    DATABASE_URL = join("", [
      "postgres:",
      "//${data.vultr_database.pg.user}:${data.vultr_database.pg.password}",
      "@${data.vultr_database.pg.host}:${data.vultr_database.pg.port}",
      "/${vultr_database_db.frankenbot.name}",
      "?sslmode=${local.dbsslmode}",
    ])
  }
}
