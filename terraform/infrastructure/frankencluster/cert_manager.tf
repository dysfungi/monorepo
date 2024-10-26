resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

# https://cert-manager.io/docs/installation/helm/
# https://artifacthub.io/packages/helm/cert-manager/cert-manager
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.15.3"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  set {
    name  = "crds.enabled"
    value = true
  }
  set_list {
    # https://cert-manager.io/docs/configuration/acme/dns01/#setting-nameservers-for-dns01-self-check
    name = "extraArgs"
    # Since Terraform Utilizes HCL as well as Helm using the Helm Template Language,
    # it's necessary to escape the `{}`, `[]`, `.`, and `,` characters twice in order
    # for it to be parsed.
    value = [
      # https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release#example-usage---chart-repository-configured-outside-of-terraform
      "--dns01-recursive-nameservers-only",
      "--dns01-recursive-nameservers=1.1.1.1:53\\,1.0.0.1:53",
      # https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/integrating-cert-manager/#deploy-cert-manager
      "--feature-gates=ExperimentalGatewayAPISupport=true",
    ]
  }
  values = [
    yamlencode({
      "nodeSelector" = local.gatewayNodeSelector
      "cainjector" = {
        "nodeSelector" = local.gatewayNodeSelector
      }
      "startupapicheck" = {
        "nodeSelector" = local.gatewayNodeSelector
      }
      "webhook" = {
        "nodeSelector" = local.gatewayNodeSelector
      }
    }),
  ]
}

# https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/#api-tokens
resource "kubernetes_secret" "cert_manager_cloudflare_creds" {
  metadata {
    name      = "cert-manager-cloudflare-credentials"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  data = {
    apiToken = var.cloudflare_api_token
  }
}

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
                  "name" = kubernetes_secret.cert_manager_cloudflare_creds.metadata[0].name
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
                  "name" = kubernetes_secret.cert_manager_cloudflare_creds.metadata[0].name
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

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role
# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#deploying-a-clusterissuer
resource "kubernetes_role" "cert_manager_secret_reader" {
  metadata {
    name      = "${helm_release.cert_manager.name}:secret-reader"
    namespace = helm_release.cert_manager.namespace
  }
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [kubernetes_secret.cert_manager_cloudflare_creds.metadata[0].name]
    verbs          = ["get", "watch"]
  }

}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding
# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#deploying-a-clusterissuer
resource "kubernetes_role_binding" "cert_manager_secret_reader" {
  metadata {
    name      = kubernetes_role.cert_manager_secret_reader.metadata[0].name
    namespace = kubernetes_role.cert_manager_secret_reader.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.cert_manager_secret_reader.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = helm_release.cert_manager.name
    namespace = helm_release.cert_manager.namespace
  }
}
