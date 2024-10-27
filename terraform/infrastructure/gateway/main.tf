terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "gateway/production/terraform.tfstate"
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
    kustomization = {
      source  = "kbst/kustomization"
      version = "0.9.6"
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

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs#example-usage
provider "kustomization" {
  kubeconfig_path = var.kubeconfig_path
}
