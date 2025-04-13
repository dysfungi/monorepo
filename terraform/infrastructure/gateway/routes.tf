# https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/https-termination/#configure-https-termination-and-routing
resource "kubernetes_manifest" "enforce_https" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "enforce-https"
      namespace = local.namespace
    }
    spec = {
      parentRefs = [
        {
          kind        = "Gateway"
          name        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          namespace   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          sectionName = "http-wildcard.frank.sh"
        },
      ]
      hostnames = [
        "*.frank.sh",
      ]
      rules = [
        {
          filters = [
            {
              type = "RequestRedirect"
              requestRedirect = {
                scheme = "https"
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
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "https-frank-sh-redirect-https-derekmfrank-com"
      namespace = local.namespace
    }
    spec = {
      parentRefs = [
        {
          kind        = "Gateway"
          name        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          namespace   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          sectionName = "http-frank.sh"
        },
        {
          kind        = "Gateway"
          name        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          namespace   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          sectionName = "https-frank.sh"
        }
      ]
      hostnames = [
        "frank.sh",
      ]
      rules = [
        {
          filters = [
            {
              type = "RequestRedirect"
              requestRedirect = {
                scheme   = "https"
                hostname = "derekmfrank.com"
              }
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "redirect_shortlinks" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "redirect-shortlinks"
      namespace = local.namespace
    }
    spec = {
      parentRefs = [
        {
          kind        = "Gateway"
          name        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          namespace   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          sectionName = "http-frank.sh"
        },
        {
          kind        = "Gateway"
          name        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          namespace   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          sectionName = "https-frank.sh"
        }
      ]
      hostnames = [
        "frank.sh",
        "dee.frank.sh",
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/events/2024-11-10/bday-5k"
              }
            },
            {
              path = {
                type  = "PathPrefix"
                value = "/2024-11-10-bday-5k"
              }
            },
            {
              path = {
                type  = "PathPrefix"
                value = "/34-bday-5k"
              }
            },
          ]
          filters = [
            {
              type = "RequestRedirect"
              requestRedirect = {
                scheme   = "https"
                hostname = "partiful.com"
                path = {
                  type            = "ReplaceFullPath"
                  replaceFullPath = "/e/BlUJWezHU3UfJI43dkur"
                }
              }
            }
          ]
        }
      ]
    }
  }
}
