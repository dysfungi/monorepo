# Provisions the app database, user, and a transaction-mode connection pool on
# the shared Vultr managed-postgres cluster (labeled "postgres"). Mirrors the
# miniflux consumer: a small pool keeps musync's slice of the ~97-connection
# cluster-wide budget minimal, which is ample for two short-lived CronJobs that
# never run concurrently (concurrencyPolicy: Forbid).
module "postgres" {
  source = "../../../../terraform/modules/vultr-managed-postgres"

  kubernetes_namespace = local.namespace
  kubeconfig_path      = var.kubeconfig_path
  vultr_api_key        = var.vultr_api_key
  app_name             = "musync"
  app_dbname           = "musync_app"
  app_username         = "musync_api"
  app_password         = var.musync_postgres_password
  connection_pool_mode = "transaction"
  connection_pool_size = 5
}
