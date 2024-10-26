resource "kubernetes_manifest" "prod_gateway" {
  depends_on = [
    helm_release.gateway,
  ]
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "Gateway"
    "metadata" = {
      "name" : "prod-web"
      "namespace" : helm_release.gateway.namespace
      "annotations" = {
        "cert-manager.io/cluster-issuer" = kubernetes_manifest.clusterissuer_letsencrypt_prod.manifest.metadata.name
      }
    }
    "spec" = {
      "gatewayClassName" = "nginx"
      "listeners" = [
        {
          "name"     = "http-frank.sh"
          "hostname" = "frank.sh"
          "port"     = 80
          "protocol" = "HTTP"
          "allowedRoutes" = {
            "namespaces" = {
              # TODO: filter for tier=prod
              "from" = "All"
            }
          }
        },
        {
          "name"     = "https-frank.sh"
          "hostname" = "frank.sh"
          "port"     = 443
          "protocol" = "HTTPS"
          "tls" = {
            "mode" = "Terminate"
            "certificateRefs" = [
              {
                "kind"      = "Secret"
                "name"      = kubernetes_manifest.certificate_wildcard_frank_sh.manifest.spec.secretName
                "namespace" = kubernetes_namespace.gateway.metadata[0].name
              }
            ]
          }
          "allowedRoutes" = {
            "namespaces" = {
              # TODO: filter for tier=prod
              "from" = "All"
            }
          }
        },
        {
          "name"     = "http-wildcard.frank.sh"
          "hostname" = "*.frank.sh"
          "port"     = 80
          "protocol" = "HTTP"
          "allowedRoutes" = {
            "namespaces" = {
              # TODO: filter for tier=prod
              "from" = "All"
            }
          }
        },
        {
          "name"     = "https-wildcard.frank.sh"
          "hostname" = "*.frank.sh"
          "port"     = 443
          "protocol" = "HTTPS"
          "tls" = {
            "mode" = "Terminate"
            "certificateRefs" = [
              {
                "kind"      = "Secret"
                "name"      = kubernetes_manifest.certificate_wildcard_frank_sh.manifest.spec.secretName
                "namespace" = kubernetes_namespace.gateway.metadata[0].name
              }
            ]
          }
          "allowedRoutes" = {
            "namespaces" = {
              # TODO: filter for tier=prod
              "from" = "All"
            }
          }
        }
      ]
    }
  }
}

# https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/https-termination/#configure-https-termination-and-routing
resource "kubernetes_manifest" "gateway_refgrant_to_certs" {
  depends_on = [
    kubernetes_manifest.prod_gateway,
  ]
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1beta1"
    "kind"       = "ReferenceGrant"
    "metadata" = {
      "name"      = "gateway-refgrant-certs"
      "namespace" = kubernetes_namespace.gateway.metadata[0].name
    }
    "spec" = {
      "to" = [
        {
          "group"     = ""
          "kind"      = "Secret"
          "namespace" = kubernetes_namespace.gateway.metadata[0].name
        }
      ]
      "from" = [
        {
          "group"     = "gateway.networking.k8s.io"
          "kind"      = "Gateway"
          "namespace" = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
        }
      ]
    }
  }
}

/* TODO: https://github.com/nginxinc/nginx-gateway-fabric/issues/1443
resource "kubernetes_manifest" "stage_gateway" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "Gateway"
    "metadata" = {
      "name" : "stage-web"
      "namespace" : helm_release.gateway.namespace
    }
    "spec" = {
      "gatewayClassName" = "nginx"
      "listeners" = [
        {
          "name"     = "http"
          "hostname" = "stage.api.frank.sh"
          "port"     = 80
          "protocol" = "HTTP"
          "allowedRoutes" = {
            "namespaces" = {
              "from" = "Selector"
              "selector" = {
                "matchLabels" = {
                  "tier" = "stage"
                }
              }
            }
          }
        }
      ]
    }
  }
}
*/
