resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
  }
}

# https://github.com/vultr/cert-manager-webhook-vultr?tab=readme-ov-file#request-a-certificate
resource "kubernetes_manifest" "certificate_letsencrypt_test" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "staging-cert-letsencrypt-test-api-frank-sh"
      "namespace" = kubernetes_namespace.staging.metadata[0].name
    }
    "spec" = {
      "commonName" = "letsencrypt-test.staging.api.frank.sh"
      "dnsNames"   = ["letsencrypt-test.staging.api.frank.sh"]
      "issuerRef" = {
        "name" = "letsencrypt-staging"
        "kind" = "ClusterIssuer"
      }
      "secretName" = "letsencrypt-test-staging-api-frank-sh-tls"
    }
  }
}
