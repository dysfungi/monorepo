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
            "requests"        = "0s"
            "backendRequests" = "0s"
          }
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
