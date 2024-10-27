variable "github_username" {
  type = string
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "kubeconfig_path" {
  type = string
}

terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "node-red/production/terraform.tfstate"
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

  registry {
    url      = "oci://ghcr.io"
    username = var.github_username
    password = var.github_token
  }
}

resource "kubernetes_namespace" "nodered" {
  metadata {
    name = "node-red"
  }
}

# https://artifacthub.io/packages/helm/node-red/node-red
resource "helm_release" "nodered" {
  name       = "node-red"
  repository = "oci://ghcr.io/schwarzit/charts"
  chart      = "node-red"
  version    = "0.33.0"
  namespace  = kubernetes_namespace.nodered.metadata[0].name

  values = [
    yamlencode({
      "env" = [
        {
          "name"  = "TZ"
          "value" = "America/Los_Angeles"
        },
      ]
      "nodeSelector" = {
        "kubernetes.io/os"        = "linux"
        "vke.vultr.com/node-pool" = "default"
      }
      # https://github.com/SchwarzIT/node-red-chart/blob/main/charts/node-red/README.md#monitoring-%EF%B8%8F
      "metrics" = {
        "enabled" = true
        "serviceMonitor" = {
          "enabled" = true
        }
      }
      "sidecar" = {
        "enabled" = true
        "extraNodeModules" = [
          "node-red-contrib-prometheus-exporter",
        ]
      }
    }),
  ]
}

resource "kubernetes_manifest" "nodered_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "node-red"
      "namespace" = helm_release.nodered.namespace
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
        "node-red.frank.sh",
        "nodered.frank.sh",
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
              "name"      = helm_release.nodered.name
              "namespace" = helm_release.nodered.namespace
              "port"      = 1880
            }
          ]
        }
      ]
    }
  }
}
