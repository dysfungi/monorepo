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

resource "kubernetes_secret" "dbmate" {
  metadata {
    name      = "automate-dbmate"
    namespace = local.namespace
  }
  data = {
    DATABASE_URL = join("", [
      "postgres:",
      "//${data.vultr_database.pg.user}:${data.vultr_database.pg.password}",
      "@${data.vultr_database.pg.host}:${data.vultr_database.pg.port}",
      "/${vultr_database_db.automate_app.name}",
      "?sslmode=${local.dbsslmode}",
    ])
  }
}

resource "kubernetes_secret" "env" {
  metadata {
    name      = "automate-env"
    namespace = local.namespace
  }
  # OAuth client credentials (DROPBOX_/TODOIST_) are NOT here: they are synced
  # from 1Password by the ESO ExternalSecret "automate-onepassword" (see
  # external_secret_automate.tf). The api Deployment mounts both Secrets via
  # env_from, so the app sees an identical merged environment. DB connection
  # details and static config stay terraform-managed because they derive from
  # other terraform resources (vultr_database_*, module.route).
  data = {
    DATABASE_HOST             = data.vultr_database.pg.host
    DATABASE_NAME             = vultr_database_db.automate_app.name
    DATABASE_PASSWORD         = vultr_database_user.automate_api.password
    DATABASE_PORT             = data.vultr_database.pg.port
    DATABASE_SSL_MODE         = local.dbsslmode
    DATABASE_USERNAME         = vultr_database_user.automate_api.username
    DROPBOX_REDIRECT_BASE_URL = "https://${module.route.primary_hostname}"
    LOGGING_FORMAT            = "plain"
    LOGGING_LEVEL             = "Information"
  }
}
