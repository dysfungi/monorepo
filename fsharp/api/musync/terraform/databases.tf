# Provisions the app database, user, and a transaction-mode connection pool on
# the shared Vultr managed-postgres cluster (labeled "postgres"). Mirrors the
# miniflux consumer: a small pool keeps musync's slice of the ~97-connection
# cluster-wide budget minimal, which is ample for two short-lived CronJobs that
# never run concurrently (concurrencyPolicy: Forbid).
# The app-role password is tofu-managed rather than op-sourced: it never leaves
# state (surfaced only inside the module's DATABASE_URL secret), so there is no
# reason to round-trip it through 1Password. alphanumeric (special = false)
# avoids URL-escaping hazards in the emitted DATABASE_URL.
resource "random_password" "pg" {
  length  = 32
  special = false
}

module "postgres" {
  source = "../../../../terraform/modules/vultr-managed-postgres"

  kubernetes_namespace = local.namespace
  kubeconfig_path      = var.kubeconfig_path
  vultr_api_key        = var.vultr_api_key
  app_name             = "musync"
  app_dbname           = "musync_app"
  app_username         = "musync_api"
  app_password         = random_password.pg.result
  connection_pool_mode = "transaction"
  connection_pool_size = 5
}
