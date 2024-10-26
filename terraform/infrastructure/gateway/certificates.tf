# https://github.com/vultr/cert-manager-webhook-vultr?tab=readme-ov-file#request-a-certificate
resource "kubernetes_manifest" "certificate_wildcard_frank_sh" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "wildcard-frank-sh"
      "namespace" = kubernetes_namespace.gateway.metadata[0].name
    }
    "spec" = {
      "commonName" = "frank.sh"
      "dnsNames" = [
        "frank.sh",
        "*.frank.sh",
        "*.api.frank.sh",
        "*.k8s.frank.sh",
      ]
      "issuerRef" = {
        "kind" = "ClusterIssuer"
        "name" = kubernetes_manifest.clusterissuer_letsencrypt_prod.manifest.metadata.name
      }
      "secretName" = "wildcard-frank-sh-tls"
    }
  }
}

# https://github.com/vultr/cert-manager-webhook-vultr?tab=readme-ov-file#request-a-certificate
resource "kubernetes_manifest" "certificate_wildcard_staging_frank_sh" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "wildcard-staging-frank-sh"
      "namespace" = kubernetes_namespace.gateway.metadata[0].name
    }
    "spec" = {
      "commonName" = "*.staging.frank.sh"
      "dnsNames" = [
        "*.stage.frank.sh",
        "*.staging.frank.sh",
      ]
      "issuerRef" = {
        "name" = "letsencrypt-staging"
        "kind" = "ClusterIssuer"
      }
      "secretName" = "wildcard-staging-frank-sh-tls"
    }
  }
}
