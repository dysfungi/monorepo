resource "kubernetes_namespace" "httpbin" {
  metadata {
    name = "httpbin"
    labels = {
      tier = "prod"
    }
  }
}

resource "helm_release" "httpbin" {
  name       = "httpbin"
  repository = "https://matheusfm.dev/charts"
  chart      = "httpbin"
  version    = "0.1.1"
  namespace  = kubernetes_namespace.httpbin.metadata[0].name
}

# https://github.com/vultr/cert-manager-webhook-vultr?tab=readme-ov-file#request-a-certificate
resource "kubernetes_manifest" "certificate_httpbin_frank_sh" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "httpbin-frank-sh"
      "namespace" = kubernetes_namespace.httpbin.metadata[0].name
    }
    "spec" = {
      "commonName" = "httpbin.frank.sh"
      "dnsNames"   = ["httpbin.frank.sh", "httpbin.api.frank.sh"]
      "issuerRef" = {
        "name" = "letsencrypt-prod"
        "kind" = "ClusterIssuer"
      }
      "secretName" = "httpbin-frank-sh-tls"
    }
  }
}

resource "kubernetes_manifest" "httpbin_route_paths" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "httpbin-paths"
      "namespace" = "httpbin"
    }
    "spec" = {
      "parentRefs" = [
        {
          "name"      = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace" = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
        }
      ]
      "hostnames" = ["api.frank.sh"]
      "rules" = [
        {
          "matches" : [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/httpbin"
              }
            }
          ]
          "filters" = [
            {
              "type" = "URLRewrite"
              "urlRewrite" = {
                "path" = {
                  "type"               = "ReplacePrefixMatch"
                  "replacePrefixMatch" = "/"
                }
              }
            }
          ]
          "backendRefs" : [
            {
              "name" = helm_release.httpbin.name
              "port" = 80
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "httpbin_route_domains" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name" : "httpbin-domains"
      "namespace" : "httpbin"
    }
    "spec" = {
      "parentRefs" = [
        {
          "name"      = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace" = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
        }
      ]
      "hostnames" = ["httpbin.frank.sh", "httpbin.api.frank.sh"]
      "rules" = [
        {
          "matches" : [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/"
              }
            }
          ]
          "backendRefs" : [
            {
              "name" = helm_release.httpbin.name
              "port" = 80
            }
          ]
        }
      ]
    }
  }
}
