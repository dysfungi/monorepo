module "route" {
  source = "../../../../terraform/modules/gateway-route"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  service_name         = one(kubernetes_service.api.metadata).name
  service_port         = 8080
  subdomain            = var.subdomain
}
