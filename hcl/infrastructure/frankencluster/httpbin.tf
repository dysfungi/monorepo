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

resource "kubernetes_manifest" "httpbin_route_path" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name" : "httpbin"
      "namespace" : "httpbin"
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
