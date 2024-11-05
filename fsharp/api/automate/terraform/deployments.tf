# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment
resource "kubernetes_deployment" "api" {
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.automate.metadata[0].name
    labels    = local.labels
  }
  spec {
    replicas = 2

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        generate_name = "api"
        namespace     = kubernetes_namespace.automate.metadata[0].name
        labels        = local.labels
      }
      spec {
        node_selector = local.node_selector
        container {
          name = "automate-api"
          image = format(
            "%s/automate/api:%s",
            data.vultr_container_registry.frankistry.urn,
            var.app_version,
          )

          port {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }

          liveness_probe {
            http_get {
              path = "/-/alive"
              port = 8080
            }
            # initial_delay_seconds = 5
            # period_seconds        = 5
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 8080
            }
            # initial_delay_seconds = 5
            # period_seconds        = 5
          }

          startup_probe {
            http_get {
              path = "/-/startup"
              port = 8080
            }
            # initial_delay_seconds = 5
            # period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "50Mi"
            }
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}
