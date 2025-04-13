module "route" {
  source = "../../modules/gateway-route"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  service_name         = helm_release.httpbin.name
  service_port         = 80
  subdomain            = var.subdomain
}
