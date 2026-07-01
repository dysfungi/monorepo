terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "terraform/frankenbot.tfstate"
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
    # (here, the ESO ExternalSecrets) without the plan-time CRD dry-run that
    # kubernetes_manifest performs. See external_secret_github_app.tf for details.
    kustomization = {
      source  = "kbst/kustomization"
      version = "~> 0.9"
    }
    # Phase 4b: the vultr provider returns to provision durable state — a
    # frankenbot DB + user on the shared Vultr managed Postgres (databases.tf).
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
    }
    # Generates the frankenbot DB app-user password (databases.tf) — a
    # machine-only credential owned by IaC rather than a 1Password item.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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
