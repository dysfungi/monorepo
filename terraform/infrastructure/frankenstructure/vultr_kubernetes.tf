locals {
  plans = {
    cloud_compute = {
      intel_oldgen_10usd = "vc2-1c-2gb"
      intel_oldgen_15usd = "vc2-2c-2gb"
      intel_oldgen_20usd = "vc2-2c-4gb"
      intel_oldgen_40usd = "vc2-4c-8gb"
    }
    cloud_gpu = {
      nvidia_a16_40usd = "vcg-a16-2c-8g-2vram" # NOTE: Was unavailable for VKE on 2025-03-29
      nvidia_a40_55usd = "vcg-a40-1c-5g-2vram"
    }
  }

}

resource "vultr_kubernetes" "k8s" {
  region           = "lax"
  label            = "frank8s"
  version          = "v1.32.2+1"
  ha_controlplanes = false
  enable_firewall  = true

  node_pools {
    node_quantity = 2
    plan          = local.plans.cloud_compute.intel_oldgen_20usd
    label         = "default"
    auto_scaler   = true
    min_nodes     = 2
    max_nodes     = 4
  }
}

resource "vultr_kubernetes_node_pools" "gateway" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 1
  plan          = local.plans.cloud_compute.intel_oldgen_10usd
  label         = "gateway"
  tag           = "gateway"
  auto_scaler   = true
  min_nodes     = 1
  max_nodes     = 3
}

resource "vultr_kubernetes_node_pools" "monitoring" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 1
  plan          = local.plans.cloud_compute.intel_oldgen_15usd
  label         = "monitoring"
  tag           = "monitoring"
  auto_scaler   = true
  min_nodes     = 1
  max_nodes     = 3
}

resource "vultr_kubernetes_node_pools" "llm" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 1
  plan          = local.plans.cloud_gpu.nvidia_a40_55usd
  label         = "llm"
  tag           = "llm"
  auto_scaler   = false
  min_nodes     = 1
  max_nodes     = 2
}
