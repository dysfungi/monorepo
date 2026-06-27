# One-time state cleanup: orphaned state from the self-hosted monitoring deprecation (commit 87f5c56,
# "feat(monitoring): deprecate self-hosted stack and migrate synthetics to OTel").
#
# That commit deleted this app's probes.tf (module "probe", which carried its own kubernetes
# provider), monitors.tf (kubernetes_manifest.api_pod_monitor) and prometheus_rules.tf
# (kubernetes_manifest.alerts) without state cleanup. The probe module's deleted provider left its
# objects orphaned in the S3 tofu state, causing `tofu apply` to fail at graph construction with
# "Error: Provider configuration not present".
#
# `destroy = false` drops the state entries WITHOUT invoking the (now deleted) module provider; the
# dangling cluster objects cascade-delete with their CRD when the Prometheus operator is removed.
# The module-address block covers all child resources of the probe instance; the pod monitor and
# alerts were root resources and need their own blocks.
#
# Transient: removable in a follow-up once this has applied cleanly once.
removed {
  from = module.probe
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_manifest.api_pod_monitor
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_manifest.alerts
  lifecycle {
    destroy = false
  }
}
