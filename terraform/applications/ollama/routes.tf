# https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/snippets/
resource "kubernetes_manifest" "long_upstream_timeouts_snippet" {
  manifest = {
    "apiVersion" = "gateway.nginx.org/v1alpha1"
    "kind"       = "SnippetsFilter"
    "metadata" = {
      "name"      = "long-upstream-timeouts"
      "namespace" = kubernetes_namespace.ollama.metadata[0].name
    }
    "spec" = {
      "snippets" = [
        {
          "context" = "http.server.location"
          "value"   = "proxy_read_timeout 1h;"
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "ollama_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "ollama"
      "namespace" = kubernetes_namespace.ollama.metadata[0].name
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = "prod-web"
          "namespace"   = "gateway"
          "sectionName" = "https-wildcard.frank.sh"
        },
      ]
      "hostnames" = [
        "llama.frank.sh",
        "ollama.frank.sh",
      ]
      "rules" = [
        {
          "timeouts" = {
            # WARN: 2025-03-30 - Nginx Gateway does not currently support HTTPRoute rules timeouts
            # https://docs.nginx.com/nginx-gateway-fabric/overview/gateway-api-compatibility/#httproute
            # Use SnippetsFilter instead:
            # https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/snippets/
            "requests"        = "0s"
            "backendRequests" = "0s"
          }
          "filters" = [
            {
              "type" = "ExtensionRef"
              "extensionRef" = {
                "group" = "gateway.nginx.org"
                "kind"  = "SnippetsFilter"
                "name"  = "long-upstream-timeouts"
              }
            },
          ]
          "matches" = [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/"
              }
            },
          ]
          "backendRefs" = [
            {
              "kind"      = "Service"
              "name"      = helm_release.ollama.name
              "namespace" = kubernetes_namespace.ollama.metadata[0].name
              "port"      = 11434
            },
          ]
        }
      ]
    }
  }
}
