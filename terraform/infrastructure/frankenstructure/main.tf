terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "terraform/frankenstructure.tfstate"
    endpoint                    = "sjc1.vultrobjects.com"
    region                      = "us-west-1"
    skip_credentials_validation = true
  }
  required_version = "~> 1.5"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.44"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "vultr" {
  api_key     = var.vultr_api_key
  rate_limit  = 100
  retry_limit = 3
}
