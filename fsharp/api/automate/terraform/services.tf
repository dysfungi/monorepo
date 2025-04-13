resource "kubernetes_service" "api" {
  metadata {
    name      = "api"
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"
    selector = {
      "app.kubernetes.io/name"     = local.labels["app.kubernetes.io/name"]
      "app.kubernetes.io/instance" = local.labels["app.kubernetes.io/instance"]
    }
    port {
      port        = 8080
      target_port = "http"
      protocol    = "TCP"
      name        = "http"
    }
  }
}
