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
  version          = "v1.36.1+1"
  ha_controlplanes = false
  enable_firewall  = true

  # Inline pool is functionally the `vhp-amd.medium` workhorse (vhp-2c-4gb-amd, $24/mo).
  # WHY the label stays `default`: in vultr provider 2.21.0 the inline pool's `plan` and
  # `label` are immutable — an Update silently drops changes to them (no-op + perpetual
  # drift), and forcing a rename (`default`->`vhp-amd.medium`) would require a pool
  # REPLACEMENT, i.e. a full cluster rebuild. So we only touch the mutable min/max here.
  # Rescaled to min1/max1: the standalone `small` pool below carries the elastic capacity;
  # this stays a single stable 4 GB medium node for workloads that want the headroom.
  node_pools {
    node_quantity = 1
    plan          = local.cpu_plans.cloud_compute.high_performance.amd_epyc_24usd
    label         = "default"
    auto_scaler   = true
    min_nodes     = 1
    max_nodes     = 1
  }

  # Don't let routine applies fight an autoscaler burst: node_quantity drifts as the
  # autoscaler adds/removes nodes, so ignore it on the inline pool.
  lifecycle {
    ignore_changes = [node_pools[0].node_quantity]
  }
}

# `vhp-amd.small` — standalone 2 GB AMD workhorse pool. Elastic capacity for the cluster:
# min2/max4 gives 3-node redundancy floor (2 small + 1 default/medium) and autoscaler
# headroom. Replaces the single-purpose `infrastructure` pool (deleted below).
#
# LABEL CAVEAT: the `.` in `vhp-amd.small` is UNPROVEN in a Vultr pool label. Kubernetes
# label VALUES permit `.`, but the Vultr API's accepted charset for pool labels is
# unconfirmed. If `tofu apply` REJECTS this label, fall back to the all-dash form
# `vhp-amd-small` (and use `tag = "small"` unchanged). Do not spend a cluster rebuild on it.
resource "vultr_kubernetes_node_pools" "small" {
  cluster_id    = vultr_kubernetes.k8s.id
  node_quantity = 2
  plan          = local.cpu_plans.cloud_compute.high_performance.amd_epyc_12usd
  label         = "vhp-amd.small"
  tag           = "small"
  auto_scaler   = true
  min_nodes     = 2
  max_nodes     = 4
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

# Node-pool naming convention: `<family>-<gputype>.<size>` (e.g. `vcg-nvidia-a40.small`),
# where `<family>` (`vcg`) and `<gputype>` derive from the Vultr plan (see `mise run plans`
# JSON `gputype` field), NOT the raw plan slug (e.g. `vcg-a40-2c-10g-4vram`). The sibling
# CPU-pool convention is `vhp-amd.<size>`.
# resource "vultr_kubernetes_node_pools" "llm" {
#   cluster_id    = vultr_kubernetes.k8s.id
#   node_quantity = 1
#   plan          = local.cpu_plans.cloud_gpu.nvidia_a40_105usd
#   label         = "vcg-nvidia-a40.small"
#   tag           = "llm"
#   auto_scaler   = false
#   min_nodes     = 1
#   max_nodes     = 2
# }
