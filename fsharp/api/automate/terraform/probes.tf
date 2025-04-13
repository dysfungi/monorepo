module "probe" {
  source = "../../../../terraform/modules/blackbox-probe"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  probe_interval       = "15s"
  probe_name           = var.subdomain
  probe_url            = "http://${module.route.primary_hostname}/-/liveness"
}
