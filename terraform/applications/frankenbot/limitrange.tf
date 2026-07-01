# Default container memory bounds so any frankenbot pod that omits limits cannot
# schedule unbounded and monopolize a node. The triage workers set a 3Gi memory
# limit explicitly; this guards against future omissions and caps ad-hoc pods.
resource "kubernetes_limit_range" "frankenbot" {
  metadata {
    name      = "frankenbot"
    namespace = local.namespace
    labels    = local.labels
  }
  spec {
    limit {
      type = "Container"
      default = {
        memory = "3Gi"
      }
      default_request = {
        memory = "1Gi"
      }
      max = {
        memory = "3Gi"
      }
    }
  }
}
