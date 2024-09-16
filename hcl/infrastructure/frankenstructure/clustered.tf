variable "email" {
  type    = string
  default = "derek@frank.sh"
}

variable "vultr_api_key" {
  type = string
}

variable "kubeconfig" {
  type = string
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  config_path = var.kubeconfig
}

# https://registry.terraform.io/providers/hashicorp/helm/latest/docs
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
}

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
}

# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr
resource "kubernetes_secret" "vultr_creds" {
  metadata {
    name      = "vultr-credentials"
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
                    "name" = "vultr-credentials"
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
                    "name" = "vultr-credentials"
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
resource "kubernetes_role" "secret_reader" {
  metadata {
    name      = "cert-manager-webhook-vultr:secret-reader"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [kubernetes_secret.vultr_creds.metadata[0].name]
    verbs          = ["get", "watch"]
  }

}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding
# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#deploying-a-clusterissuer
resource "kubernetes_role_binding" "secret_reader" {
  metadata {
    name      = "cert-manager-webhook-vultr:secret-reader"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.secret_reader.metadata[0].name
  }
  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = helm_release.cert_manager_webhook.name
  }
}
