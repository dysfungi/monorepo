# Optional per-route upstream read-timeout override for long-lived streaming
# connections (SSE/WebSocket). NGF ignores native HTTPRoute timeouts, so we raise
# nginx's proxy_read_timeout via a SnippetsFilter. Gated on var.upstream_read_timeout
# so existing callers (which leave it null) emit no SnippetsFilter and an unchanged
# HTTPRoute. https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/snippets/
resource "kubernetes_manifest" "upstream_read_timeout" {
  count = var.upstream_read_timeout == null ? 0 : 1

  manifest = {
    apiVersion = "gateway.nginx.org/v1alpha1"
    kind       = "SnippetsFilter"
    metadata = {
      name      = "${var.subdomain}-upstream-read-timeout"
      namespace = var.kubernetes_namespace
    }
    spec = {
      snippets = [
        {
          context = "http.server.location"
          value   = "proxy_read_timeout ${var.upstream_read_timeout};"
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "route" {
  # Ensure the SnippetsFilter exists before the HTTPRoute references it (no-op when
  # upstream_read_timeout is null => count 0). depends_on is a meta-arg, so this does
  # not alter the rendered HTTPRoute => still zero plan-diff for existing callers.
  depends_on = [kubernetes_manifest.upstream_read_timeout]

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
        merge(
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
          },
          # Attach the SnippetsFilter only when a timeout override is set, so callers
          # that leave upstream_read_timeout null produce a byte-identical rule.
          var.upstream_read_timeout == null ? {} : {
            filters = [
              {
                type = "ExtensionRef"
                extensionRef = {
                  group = "gateway.nginx.org"
                  kind  = "SnippetsFilter"
                  name  = "${var.subdomain}-upstream-read-timeout"
                }
              },
            ]
          },
        )
      ]
    }
  }
}
