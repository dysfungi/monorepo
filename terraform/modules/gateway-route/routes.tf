resource "kubernetes_manifest" "route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = var.subdomain
      namespace = var.kubernetes_namespace
    }
    spec = {
      parentRefs = [
        {
          kind        = "Gateway"
          name        = "prod-web"
          namespace   = "gateway"
          sectionName = "https-wildcard.${var.root_domain}"
        },
      ]
      hostnames = [
        "${var.subdomain}.${var.root_domain}",
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            },
          ]
          backendRefs = [
            {
              kind      = "Service"
              name      = var.service_name
              namespace = var.kubernetes_namespace
              port      = var.service_port
              weight    = 1
            },
          ]
        }
      ]
    }
  }
}
