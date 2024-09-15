# https://registry.terraform.io/providers/vultr/vultr/latest/docs
# https://www.vultr.com/api/#section/Introduction

terraform {
  backend "s3" {
    bucket                      = "frankenstructure"
    key                         = "frankenstructure/production/terraform.tfstate"
    endpoint                    = "sjc1.vultrobjects.com"
    region                      = "us-west-1"
    skip_credentials_validation = true
  }
  required_version = ">= 1.5.7"
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "2.19.0"
    }
  }
}

# Configure the Vultr Provider
provider "vultr" {
  rate_limit  = 100
  retry_limit = 3
}

resource "vultr_object_storage" "frankenstorage" {
  cluster_id = 5
  label      = "frankenstorage"
}

resource "vultr_ssh_key" "dmf" {
  name    = "dmf@macbookpro2023"
  ssh_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPI+zflKPFKFTsZXQXGKN1cvOTnJLStl6s3QfxHTpw+M derek@frank.sh"
}

resource "vultr_vpc2" "frankenetwork" {
  description = "frankenetwork"
  region      = "lax"
}
