resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

# https://cert-manager.io/docs/installation/helm/
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.15.3"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  set {
    name  = "crds.enabled"
    value = "true"
  }
  set_list {
    # https://cert-manager.io/docs/configuration/acme/dns01/#setting-nameservers-for-dns01-self-check
    name = "extraArgs"
    # Since Terraform Utilizes HCL as well as Helm using the Helm Template Language,
    # it's necessary to escape the `{}`, `[]`, `.`, and `,` characters twice in order
    # for it to be parsed.
    # https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release#example-usage---chart-repository-configured-outside-of-terraform
    value = ["--dns01-recursive-nameservers-only", "--dns01-recursive-nameservers=1.1.1.1:53\\,1.0.0.1:53"]
  }
}

# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr
resource "kubernetes_secret" "cert_manager_vultr_creds" {
  metadata {
    name      = "cert-manager-vultr-credentials"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  data = {
    apiKey = var.vultr_api_key
  }
}

# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#installing-the-chart
resource "helm_release" "cert_manager_webhook" {
  name       = "cert-manager-webhook-vultr"
  repository = "https://vultr.github.io/helm-charts"
  chart      = "cert-manager-webhook-vultr"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
}

# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#deploying-a-clusterissuer
# https://stackoverflow.com/a/71037775
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest
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
              "webhook" = {
                "groupName"  = "acme.vultr.com"
                "solverName" = "vultr"
                "config" = {
                  "apiKeySecretRef" = {
                    "key"  = "apiKey"
                    "name" = kubernetes_secret.cert_manager_vultr_creds.metadata[0].name
                  }
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
              "webhook" = {
                "groupName"  = "acme.vultr.com"
                "solverName" = "vultr"
                "config" = {
                  "apiKeySecretRef" = {
                    "key"  = "apiKey"
                    "name" = kubernetes_secret.cert_manager_vultr_creds.metadata[0].name
                  }
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
resource "kubernetes_role" "cert_manager_webhook_secret_reader" {
  metadata {
    name      = "${helm_release.cert_manager_webhook.name}:secret-reader"
    namespace = helm_release.cert_manager_webhook.namespace
  }
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [kubernetes_secret.cert_manager_vultr_creds.metadata[0].name]
    verbs          = ["get", "watch"]
  }

}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding
# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#deploying-a-clusterissuer
resource "kubernetes_role_binding" "cert_manager_webhook_secret_reader" {
  metadata {
    name      = kubernetes_role.cert_manager_webhook_secret_reader.metadata[0].name
    namespace = kubernetes_role.cert_manager_webhook_secret_reader.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.cert_manager_webhook_secret_reader.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = helm_release.cert_manager_webhook.name
    namespace = helm_release.cert_manager_webhook.namespace
  }
}
