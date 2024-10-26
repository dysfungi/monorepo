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

  node_pools {
    node_quantity = 1
    plan          = "vc2-2c-2gb"
    label         = "default"
    auto_scaler   = true
    min_nodes     = 1
    max_nodes     = 3
  }
}

resource "vultr_kubernetes_node_pools" "gateway" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 1
  plan          = "vc2-1c-2gb"
  label         = "gateway"
  tag           = "gateway"
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

resource "vultr_kubernetes_node_pools" "production" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 2
  plan          = "vc2-2c-4gb"
  label         = "production"
  tag           = "production"
  auto_scaler   = true
  min_nodes     = 2
  max_nodes     = 3
}

resource "vultr_vpc" "k8s" {
  # id = "0dcffa14-ac8e-49cb-8710-3dcc46a97f1f"
  region = "lax"
}

resource "vultr_database" "pg" {
  # max connections: 97
  label                   = "postgres"
  tag                     = "postgres"
  plan                    = "vultr-dbaas-startup-cc-hp-amd-1-64-2"
  region                  = "lax"
  vpc_id                  = vultr_vpc.k8s.id
  database_engine         = "pg"
  database_engine_version = "16"
  cluster_time_zone       = "UTC"
  maintenance_dow         = "sunday"
  maintenance_time        = "03:00"
}
