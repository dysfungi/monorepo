terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "terraform/external-secrets.tfstate"
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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    # The kbst kustomization provider is the repo's mechanism for applying raw
    # manifests / single custom-resource instances (see cluster_secret_store.tf
    # for why it is used here instead of kubernetes_manifest).
    kustomization = {
      source  = "kbst/kustomization"
      version = "~> 0.9"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# https://registry.terraform.io/providers/hashicorp/helm/latest/docs
# No registry{} block: ESO and reloader charts are served from plain HTTPS chart
# repositories, not an OCI registry, so no ghcr.io credentials are required.
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs#example-usage
provider "kustomization" {
  kubeconfig_path = var.kubeconfig_path
}
