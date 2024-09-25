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
        "kind" = "ClusterIssuer"
        "name" = kubernetes_manifest.clusterissuer_letsencrypt_prod.manifest.metadata.name
      }
      "secretName" = "httpbin-frank-sh-tls"
    }
  }
}

resource "kubernetes_manifest" "httpbin_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "httpbin"
      "namespace" = kubernetes_namespace.httpbin.metadata[0].name
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          "sectionName" = "https-wildcard.frank.sh"
        }
      ]
      "hostnames" = [
        "httpbin.frank.sh",
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
              "namespace" = kubernetes_namespace.httpbin.metadata[0].name
              "port"      = 80
            }
          ]
        }
      ]
    }
  }
}
