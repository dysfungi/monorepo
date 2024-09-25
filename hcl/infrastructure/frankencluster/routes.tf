resource "kubernetes_namespace" "route" {
  metadata {
    name = "route"
  }
}

# https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/https-termination/#configure-https-termination-and-routing
resource "kubernetes_manifest" "enforce_https" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "enforce-https"
      "namespace" = kubernetes_namespace.route.metadata[0].name
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          "sectionName" = "http-wildcard.frank.sh"
        },
      ]
      "hostnames" = [
        "*.frank.sh",
      ]
      "rules" = [
        {
          "filters" = [
            {
              "type" = "RequestRedirect"
              "requestRedirect" = {
                "scheme" = "https"
                "port"   = 443
              }
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "https_redirect_frank_sh" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "https-frank-sh-redirect-https-derekmfrank-com"
      "namespace" = kubernetes_namespace.route.metadata[0].name
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          "sectionName" = "http-frank.sh"
        },
        {
          "kind"        = "Gateway"
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          "sectionName" = "https-frank.sh"
        }
      ]
      "hostnames" = [
        "frank.sh",
      ]
      "rules" = [
        {
          "filters" = [
            {
              "type" = "RequestRedirect"
              "requestRedirect" = {
                "scheme"   = "https"
                "hostname" = "derekmfrank.com"
                "port"     = 443
              }
            }
          ]
        }
      ]
    }
  }
}
