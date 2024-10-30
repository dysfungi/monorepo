resource "kubernetes_manifest" "httpbin_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = helm_release.httpbin.name
      "namespace" = helm_release.httpbin.namespace
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = "prod-web"
          "namespace"   = "gateway"
          "sectionName" = "https-wildcard.${var.root_domain}"
        }
      ]
      "hostnames" = [
        local.hostname,
      ]
      "rules" = [
        {
          "matches" = [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/"
              }
            }
          ]
          "backendRefs" = [
            {
              "kind"      = "Service"
              "name"      = helm_release.httpbin.name
              "namespace" = helm_release.httpbin.namespace
              "port"      = 80
            }
          ]
        }
      ]
    }
  }
}
