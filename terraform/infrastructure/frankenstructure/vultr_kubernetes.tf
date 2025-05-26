locals {
  cpu_plans = {
    cloud_compute = {
      # https://www.vultr.com/pricing/#cloud-compute
      regular_performance = {
        intel_oldgen_10usd = "vc2-1c-2gb"
        intel_oldgen_15usd = "vc2-2c-2gb"
        intel_oldgen_20usd = "vc2-2c-4gb"
        intel_oldgen_40usd = "vc2-4c-8gb"
      }
      high_performance = {
        amd_epyc_06usd   = "vhp-1c-1gb-amd"
        amd_epyc_12usd   = "vhp-1c-2gb-amd"
        amd_epyc_18usd   = "vhp-2c-2gb-amd"
        amd_epyc_24usd   = "vhp-2c-4gb-amd"
        amd_epyc_48usd   = "vhp-4c-8gb-amd"
        intel_xeon_24usd = "vhp-2c-4gb-intel"
      }
      high_frequency = {
      }
    }
    optimized_compute = {
      # https://www.vultr.com/pricing/#optimized-cloud-compute
      general_purpose = {
      }
      cpu_optimized = {
      }
      memory_optimized = {
      }
      storage_optimized = {
      }
    }
    cloud_gpu = {
      # https://www.vultr.com/pricing/#cloud-gpu
      nvidia_a16_43usd  = "vcg-a16-2c-8g-2vram"  # NOTE: Was unavailable for VKE on 2025-03-29
      nvidia_a16_86usd  = "vcg-a16-2c-16g-4vram" # NOTE: Was unavailable for VKE on 2025-03-29
      nvidia_a40_55usd  = "vcg-a40-1c-5g-2vram"
      nvidia_a40_105usd = "vcg-a40-2c-10g-4vram"
      nvidia_a100_90usd = "vcg-a100-1c-6g-4vram" # NOTE: Was unavailable for VKE on 2025-03-29
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
    node_quantity = 1
    plan          = local.cpu_plans.cloud_compute.high_performance.amd_epyc_24usd
    label         = "default"
    auto_scaler   = true
    min_nodes     = 1
    max_nodes     = 2
  }
}

# resource "vultr_kubernetes_node_pools" "temp" {
#   cluster_id    = vultr_kubernetes.k8s.id
#   node_quantity = 2
#   plan          = local.cpu_plans.cloud_compute.high_performance.amd_epyc_24usd
#   label         = "temp"
#   tag           = "temp"
#   auto_scaler   = true
#   min_nodes     = 1
#   max_nodes     = 2
# }

resource "vultr_kubernetes_node_pools" "infrastructure" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 2
  plan          = local.cpu_plans.cloud_compute.high_performance.amd_epyc_24usd
  label         = "infrastructure"
  tag           = "infrastructure"
  auto_scaler   = true
  min_nodes     = 1
  max_nodes     = 2
}

# resource "vultr_kubernetes_node_pools" "llm" {
#   cluster_id    = vultr_kubernetes.k8s.id
#   node_quantity = 1
#   plan          = local.cpu_plans.cloud_gpu.nvidia_a40_105usd
#   label         = "llm"
#   tag           = "llm"
#   auto_scaler   = false
#   min_nodes     = 1
#   max_nodes     = 2
# }
