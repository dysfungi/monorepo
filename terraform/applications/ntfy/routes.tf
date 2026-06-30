module "route" {
  source = "../../modules/gateway-route"

  kubeconfig_path      = var.kubeconfig_path
  kubernetes_namespace = local.namespace
  service_name         = helm_release.ntfy.name
  service_port         = 80
  subdomain            = var.subdomain

  # ntfy subscriptions are long-lived SSE/WebSocket streams; NGF's default ~60s
  # proxy_read_timeout would sever idle connections. This raises it via a
  # SnippetsFilter (NGF ignores native HTTPRoute timeouts).
  upstream_read_timeout = "1h"
}
