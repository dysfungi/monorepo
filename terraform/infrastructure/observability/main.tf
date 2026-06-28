terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "terraform/observability.tfstate"
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
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.0"
    }
    honeycombio = {
      source  = "honeycombio/honeycombio"
      version = "~> 0.35.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
    # The kbst kustomization provider is the repo's mechanism for applying raw
    # manifests / single custom-resource instances (see
    # external_secret_grafana_cloud.tf for why it is used instead of
    # kubernetes_manifest).
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
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

provider "healthchecksio" {
  api_key = var.healthchecksio_api_key
}

provider "honeycombio" {
  # v2 Management key (api_key_id/secret) powers environment/key management; the
  # v1 Configuration key (api_key) is required for triggers and recipients. The
  # provider accepts both simultaneously.
  api_key_id     = var.honeycomb_key_id
  api_key_secret = var.honeycomb_key_secret
  api_key        = var.honeycomb_api_key
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs#example-usage
provider "kustomization" {
  kubeconfig_path = var.kubeconfig_path
}
