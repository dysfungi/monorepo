resource "kubernetes_config_map" "dbmigrations" {
  metadata {
    name      = "musync-dbmigrations"
    namespace = local.namespace
    labels = merge(local.labels, {
      "app.kubernetes.io/instance" = "dbmigrations"
    })
  }

  data = {
    for migration in fileset("${path.module}/../db/migrations", "*.sql") :
    migration => file("${path.module}/../db/migrations/${migration}")
  }
}
