terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "terraform/observability.tfstate"
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
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.0"
    }
    honeycombio = {
      source  = "honeycombio/honeycombio"
      version = "~> 0.35.0"
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

provider "healthchecksio" {
  api_key = var.healthchecksio_api_key
}

provider "honeycombio" {
  api_key_id     = var.honeycomb_key_id
  api_key_secret = var.honeycomb_key_secret
}
