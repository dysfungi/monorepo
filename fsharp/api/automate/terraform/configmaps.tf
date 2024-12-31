resource "kubernetes_config_map" "dbmigrations" {
  metadata {
    name      = "automate-api-dbmigrations"
    namespace = kubernetes_namespace.automate.metadata[0].name
    labels = merge(local.labels, {
      "app.kubernetes.io/instance" = "dbmigrations"
    })
  }

  data = {
    for migration in fileset("${path.module}/../db/migrations", "*.sql") :
    migration => file("${path.module}/../db/migrations/${migration}")
  }
}
