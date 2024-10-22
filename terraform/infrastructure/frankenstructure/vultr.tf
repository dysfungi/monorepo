# https://registry.terraform.io/providers/vultr/vultr/latest/docs
# https://www.vultr.com/api/#section/Introduction
variable "vultr_api_key" {
  type      = string
  sensitive = true
}

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
  api_key     = var.vultr_api_key
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

resource "vultr_kubernetes" "k8s" {
  region           = "lax"
  label            = "frank8s"
  version          = "v1.31.0+1"
  ha_controlplanes = false
  enable_firewall  = true
}

resource "vultr_kubernetes_node_pools" "foundation" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 1
  plan          = "vc2-1c-2gb"
  label         = "foundation"
  tag           = "foundation"
  auto_scaler   = true
  min_nodes     = 1
  max_nodes     = 3
}

resource "vultr_kubernetes_node_pools" "monitoring" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 2
  plan          = "vc2-2c-2gb"
  label         = "monitoring"
  tag           = "monitoring"
  auto_scaler   = true
  min_nodes     = 2
  max_nodes     = 3
}

resource "vultr_kubernetes_node_pools" "np2cpu2mem" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 1
  plan          = "vc2-2c-2gb"
  label         = "frankenodes2cpu2ram"
  auto_scaler   = true
  min_nodes     = 1
  max_nodes     = 3
}
