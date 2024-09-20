terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "frankencluster/production/terraform.tfstate"
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
