# One-time state cleanup: orphaned state from the self-hosted monitoring deprecation (commit 87f5c56,
# "feat(monitoring): deprecate self-hosted stack and migrate synthetics to OTel").
#
# The blackbox-probe module declared its OWN `provider "kubernetes"` block. Deleting the module
# removed that provider while its objects (Probe, monitoring.coreos.com/v1) were still recorded in
# the S3 tofu state, causing `tofu apply` to fail at graph construction with
# "Error: Provider configuration not present".
#
# `destroy = false` drops the state entries WITHOUT invoking the (now deleted) module provider; the
# dangling cluster objects cascade-delete with their CRD when the Prometheus operator is removed.
# A module-address `removed` block covers all child resources of the instance.
#
# Transient: removable in a follow-up once this has applied cleanly once.
removed {
  from = module.probe
  lifecycle {
    destroy = false
  }
}
