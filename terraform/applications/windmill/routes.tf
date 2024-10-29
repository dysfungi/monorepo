resource "kubernetes_manifest" "windmill_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "windmill"
      "namespace" = kubernetes_namespace.windmill.metadata[0].name
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
        "windmill.frank.sh",
      ]
      "rules" = [
        {
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
              "name"      = "${helm_release.windmill.name}-app"
              "namespace" = kubernetes_namespace.windmill.metadata[0].name
              "port"      = 8000
            },
          ]
        }
      ]
    }
  }
}
