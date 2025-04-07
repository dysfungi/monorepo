resource "kubernetes_secret" "db" {
  metadata {
    name      = "${var.app_name}-postgres"
    namespace = var.kubernetes_namespace
  }
  data = {
    ADMIN_URL = local.admin_url
    APP_URL   = local.app_url
  }
}
