module "postgres" {
  source = "../../modules/vultr-managed-postgres"

  kubernetes_namespace = local.namespace
  kubeconfig_path      = var.kubeconfig_path
  vultr_api_key        = var.vultr_api_key
  app_name             = "miniflux"
  app_dbname           = "miniflux"
  app_username         = "miniflux_app"
  app_password         = var.miniflux_postgres_password
  connection_pool_size = 5
}
