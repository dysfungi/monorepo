resource "kubernetes_secret" "db" {
  metadata {
    name      = "windmill-databases"
    namespace = kubernetes_namespace.windmill.metadata[0].name
  }
  data = {
    appUrl = format(
      "postgres://%v:%v@%v:%v/%v?sslmode=%v",
      vultr_database_user.windmill_app.username,
      vultr_database_user.windmill_app.password,
      data.vultr_database.pg.host,
      data.vultr_database.pg.port,
      vultr_database_db.windmill_app.name,
      # https://www.postgresql.org/docs/current/libpq-ssl.html#LIBPQ-SSL-PROTECTION
      "require",
    )
  }
}
