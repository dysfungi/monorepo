variable "kubeconfig_path" {
  type = string
}

terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "windmill/production/terraform.tfstate"
    endpoint                    = "sjc1.vultrobjects.com"
    region                      = "us-west-1"
    skip_credentials_validation = true
  }
  required_version = ">= 1.5.7"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.32.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.15.0"
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

resource "kubernetes_namespace" "windmill" {
  metadata {
    name = "windmill"
  }
}

# https://www.windmill.dev/docs/advanced/self_host#helm-chart
# https://artifacthub.io/packages/helm/windmill/windmill
resource "helm_release" "windmill" {
  name       = "windmill"
  repository = "https://windmill-labs.github.io/windmill-helm-charts"
  chart      = "windmill"
  version    = "2.0.300"
  namespace  = kubernetes_namespace.windmill.metadata[0].name

  values = [
    yamlencode({
      "hub" = {
        "baseDomain"   = "windmill.frank.sh"
        "baseProtocol" = "https"
        "resources" = {
          "limits" = {
            "cpu"    = "1"
            "memory" = "512Mi"
          }
        }
      }
      "windmill" = {
        "app" = {
          "resources" = {
            "limits" = {
              "cpu"    = "1"
              "memory" = "512Mi"
            }
          }
        }
        "baseDomain"   = "windmill.frank.sh"
        "baseProtocol" = "https"
        "cookieDomain" = "windmill.frank.sh"
        "workerGroups" = [
          {
            "name"     = "default"
            "replicas" = 2
            "mode"     = "worker"
            "podSecurityContext" = {
              "runAsUser"    = 0
              "runAsNonRoot" = false
            }
            "resources" = {
              "limits" = {
                "cpu"    = "1"
                "memory" = "512Mi"
              }
            }
            "terminationGracePeriod" = 300
          },
          {
            "name"     = "native"
            "replicas" = 0
          },
          {
            "name"     = "gpu"
            "replicas" = 0
          },
        ]
      }
    }),
  ]
}

resource "kubernetes_manifest" "windmill_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "windmill"
      "namespace" = kubernetes_namespace.windmill.metadata[0].name
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = "prod-web"
          "namespace"   = "nginx-gateway"
          "sectionName" = "https-wildcard.frank.sh"
        }
      ]
      "hostnames" = [
        "windmill.frank.sh",
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
              "name"      = helm_release.windmill.name
              "namespace" = kubernetes_namespace.windmill.metadata[0].name
              "port"      = 80
            }
          ]
        }
      ]
    }
  }
}
