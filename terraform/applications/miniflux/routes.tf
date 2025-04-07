module "route" {
  source = "../../modules/gateway-route"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  service_name         = helm_release.miniflux.name
  service_port         = 8080
  subdomain            = "miniflux"
}
