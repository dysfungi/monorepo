variable "kubeconfig_path" {
  type = string
}

terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "terraform/n8n.tfstate"
    endpoint                    = "sjc1.vultrobjects.com"
    region                      = "us-west-1"
    skip_credentials_validation = true
  }
  required_version = "~> 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# https://registry.terraform.io/providers/hashicorp/helm/latest/docs
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

resource "kubernetes_namespace" "n8n" {
  metadata {
    name = "n8n"
  }
}

# https://artifacthub.io/packages/helm/open-8gears/n8n
resource "helm_release" "n8n" {
  name       = "n8n"
  repository = "oci://8gears.container-registry.com/library"
  chart      = "n8n"
  version    = "0.25.2"
  namespace  = kubernetes_namespace.n8n.metadata[0].name

  values = [
    yamlencode({
      "nodeSelector" = {
        "kubernetes.io/os"        = "linux"
        "vke.vultr.com/node-pool" = "default"
      }
      "generic" = {
        "timezone" = "America/Los_Angeles"
      }
      "extraEnv" = {
        "WEBHOOK_TUNNEL_URL" = "https://n8n.frank.sh/"
      }
    }),
  ]
}

resource "kubernetes_manifest" "n8n_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "n8n"
      "namespace" = helm_release.n8n.namespace
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = "prod-web"
          "namespace"   = "gateway"
          "sectionName" = "https-wildcard.frank.sh"
        }
      ]
      "hostnames" = [
        "n8n.frank.sh",
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
              "name"      = helm_release.n8n.name
              "namespace" = helm_release.n8n.namespace
              "port"      = 80
            }
          ]
        }
      ]
    }
  }
}
