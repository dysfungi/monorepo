resource "kubernetes_manifest" "automate_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = kubernetes_service.api.metadata[0].name
      "namespace" = kubernetes_service.api.metadata[0].namespace
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
              "name"      = kubernetes_service.api.metadata[0].name
              "namespace" = kubernetes_service.api.metadata[0].namespace
              "port"      = 8080
            }
          ]
        }
      ]
    }
  }
}
