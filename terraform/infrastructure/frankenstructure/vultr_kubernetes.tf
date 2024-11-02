resource "vultr_kubernetes" "k8s" {
  region           = "lax"
  label            = "frank8s"
  version          = "v1.31.0+1"
  ha_controlplanes = false
  enable_firewall  = true

  node_pools {
    node_quantity = 2
    plan          = "vc2-2c-4gb"
    label         = "default"
    auto_scaler   = true
    min_nodes     = 2
    max_nodes     = 4
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
  node_quantity = 1
  plan          = "vc2-2c-2gb"
  label         = "monitoring"
  tag           = "monitoring"
  auto_scaler   = true
  min_nodes     = 1
  max_nodes     = 3
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
