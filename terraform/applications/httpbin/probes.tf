module "probe" {

  source = "../../modules/blackbox-probe"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  probe_interval       = "15s"
  probe_name           = helm_release.httpbin.name
  probe_url            = "http://${module.route.primary_hostname}/ip"
}
