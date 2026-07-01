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
    # NOTE: the vultr provider is intentionally ABSENT in Phase 3 (slim: no CR
    # data source, no managed Postgres). It returns in Phase 4 with durable state.
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs#example-usage
provider "kustomization" {
  kubeconfig_path = var.kubeconfig_path
}
