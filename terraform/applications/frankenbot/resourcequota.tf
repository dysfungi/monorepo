# Backstop for the 4GB cluster: caps total frankenbot memory / pods / Jobs so a
# runaway dispatch (e.g. a concurrency-cap regression) cannot exhaust a node.
# Sized for roughly two concurrent 3Gi workers plus the dispatcher and overhead.
resource "kubernetes_resource_quota" "frankenbot" {
  metadata {
    name      = "frankenbot"
    namespace = local.namespace
    labels    = local.labels
  }
  spec {
    hard = {
      "requests.memory"  = "2Gi"
      "limits.memory"    = "8Gi"
      "pods"             = "8"
      "count/jobs.batch" = "6"
    }
  }
}
