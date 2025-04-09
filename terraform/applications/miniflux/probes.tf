module "probe" {
  source = "../../modules/blackbox-probe"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  probe_name           = helm_release.miniflux.name
  probe_url            = "http://${module.route.primary_hostname}/healthcheck"
}
