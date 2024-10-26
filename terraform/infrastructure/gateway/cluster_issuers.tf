# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#deploying-a-clusterissuer
# https://stackoverflow.com/a/71037775
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest
# https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/#api-tokens
resource "kubernetes_manifest" "clusterissuer_letsencrypt_staging" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "letsencrypt-staging"
    }
    "spec" = {
      "acme" = {
        "email" = var.email
        "privateKeySecretRef" = {
          "name" = "letsencrypt-staging"
        }
        "server" = "https://acme-staging-v02.api.letsencrypt.org/directory"
        "solvers" = [
          {
            "dns01" = {
              "cloudflare" = {
                "apiTokenSecretRef" = {
                  "name" = kubernetes_secret.cloudflare.metadata[0].name
                  "key"  = "apiToken"
                }
              }
            }
          },
        ]
      }
    }
  }
}

resource "kubernetes_manifest" "clusterissuer_letsencrypt_prod" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "letsencrypt-prod"
    }
    "spec" = {
      "acme" = {
        "email" = var.email
        "privateKeySecretRef" = {
          "name" = "letsencrypt-prod"
        }
        "server" = "https://acme-v02.api.letsencrypt.org/directory"
        "solvers" = [
          {
            "dns01" = {
              "cloudflare" = {
                "apiTokenSecretRef" = {
                  "name" = kubernetes_secret.cloudflare.metadata[0].name
                  "key"  = "apiToken"
                }
              }
            }
          },
        ]
      }
    }
  }
}
