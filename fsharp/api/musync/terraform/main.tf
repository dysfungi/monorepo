terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "terraform/musync.tfstate"
    endpoint                    = "sjc1.vultrobjects.com"
    region                      = "us-west-1"
    skip_credentials_validation = true
    use_lockfile                = true
  }
  required_version = ">= 1.10"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
    # The kbst kustomization provider applies single custom-resource instances
    # (here, the ESO ExternalSecret) without the plan-time CRD dry-run that
    # kubernetes_manifest performs. See external_secret_musync.tf for details.
    kustomization = {
      source  = "kbst/kustomization"
      version = "~> 0.9"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "vultr" {
  api_key     = var.vultr_api_key
  rate_limit  = 100
  retry_limit = 3
}

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs#example-usage
provider "kustomization" {
  kubeconfig_path = var.kubeconfig_path
}
