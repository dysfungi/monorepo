variable "kubeconfig_path" {
  type = string
}

terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "httpbin/production/terraform.tfstate"
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

resource "kubernetes_namespace" "httpbin" {
  metadata {
    name = "httpbin"
  }
}

resource "helm_release" "httpbin" {
  name       = "httpbin"
  repository = "https://matheusfm.dev/charts"
  chart      = "httpbin"
  version    = "0.1.1"
  namespace  = kubernetes_namespace.httpbin.metadata[0].name

  set {
    name  = "replicaCount"
    value = "2"
  }
}

resource "kubernetes_manifest" "httpbin_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "httpbin"
      "namespace" = kubernetes_namespace.httpbin.metadata[0].name
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
        "httpbin.frank.sh",
        "httpbingo.frank.sh",
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
              "name"      = helm_release.httpbin.name
              "namespace" = kubernetes_namespace.httpbin.metadata[0].name
              "port"      = 80
            }
          ]
        }
      ]
    }
  }
}
