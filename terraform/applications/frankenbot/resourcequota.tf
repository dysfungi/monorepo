# Backstop: caps total frankenbot memory / pods / Jobs so a runaway dispatch
# (e.g. a concurrency-cap regression) cannot exhaust the node pool.
#
# Actual per-pod sizing (source of truth):
#   - triage workers  (dispatch.py): requests cpu 250m / mem 1Gi, limit mem 3Gi
#   - dispatcher (cronjob_dispatcher.tf): requests mem 256Mi, limit mem 512Mi
#   - default max_concurrent_jobs = 1 (config.py)
#
# requests.memory (4Gi): schedulable floor. Comfortably fits the dispatcher
# (256Mi) plus ~2 concurrent workers (2×1Gi) with headroom — i.e. room to bump
# max_concurrent_jobs to 2 without starving the dispatcher, while the default of
# 1 leaves ample slack.
#
# limits.memory (10Gi): a POOL-WIDE ceiling, not a single-node one. Triage
# workers are pinned (required nodeAffinity) to the `infrastructure` nodepool,
# which autoscales 1→3 nodes (≈12Gi aggregate). 10Gi lets ~3 concurrent 3Gi
# worker limits + the dispatcher fit across the scaled-out pool while still
# capping total burst below pool capacity. (Per-container memory is also bounded
# by the LimitRange at 3Gi.)
resource "kubernetes_resource_quota" "frankenbot" {
  metadata {
    name      = "frankenbot"
    namespace = local.namespace
    labels    = local.labels
  }
  spec {
    hard = {
      "requests.memory"  = "4Gi"
      "limits.memory"    = "10Gi"
      "pods"             = "8"
      "count/jobs.batch" = "6"
    }
  }
}
