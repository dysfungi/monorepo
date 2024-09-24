resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
  }
}

# https://github.com/vultr/cert-manager-webhook-vultr?tab=readme-ov-file#request-a-certificate
resource "kubernetes_manifest" "certificate_wildcard_staging_frank_sh" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "wildcard-staging-frank-sh"
      "namespace" = kubernetes_namespace.staging.metadata[0].name
    }
    "spec" = {
      "commonName" = "*.staging.frank.sh"
      "dnsNames"   = ["*.staging.frank.sh"]
      "issuerRef" = {
        "name" = "letsencrypt-staging"
        "kind" = "ClusterIssuer"
      }
      "secretName" = "wildcard-staging-frank-sh-tls"
    }
  }
}
