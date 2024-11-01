# https://registry.terraform.io/providers/vultr/vultr/latest/docs
# https://www.vultr.com/api/#section/Introduction
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

  /*
  node_pools {
    node_quantity = 1
    plan          = "vc2-2c-2gb"
    label         = "default"
    auto_scaler   = true
    min_nodes     = 1
    max_nodes     = 3
  }
  */
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
  min_nodes     = 1
  max_nodes     = 3
}

resource "vultr_kubernetes_node_pools" "production" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 2
  plan          = "vc2-2c-4gb"
  label         = "production"
  tag           = "production"
  auto_scaler   = true
  min_nodes     = 1
  max_nodes     = 4
}

resource "vultr_kubernetes_node_pools" "llm" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 1
  # plan          = "vcg-a16-2c-8g-2vram"
  plan        = "vc2-4c-8gb"
  label       = "llm"
  tag         = "llm"
  auto_scaler = false
  min_nodes   = 1
  max_nodes   = 2
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
  maintenance_time        = "10:00"
  trusted_ips = [
    format("%v/%v", vultr_vpc.k8s.v4_subnet, vultr_vpc.k8s.v4_subnet_mask),
    vultr_kubernetes.k8s.service_subnet,
    vultr_kubernetes.k8s.cluster_subnet,
    format("%v/32", var.home_ip),
  ]
}
