# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment
resource "kubernetes_deployment" "api" {
  metadata {
    name      = "automate-api"
    namespace = local.namespace
    labels    = local.labels
  }
  spec {
    replicas = 2

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        generate_name = "automate-api"
        namespace     = local.namespace
        labels        = local.labels
      }
      spec {
        affinity {
          # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
          node_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 2
              preference {
                match_expressions {
                  key      = "vke.vultr.com/node-pool"
                  operator = "In"
                  values = [
                    "default",
                    local.namespace,
                  ]
                }
              }
            }
          }
        }
        node_selector = local.node_selector

        image_pull_secrets {
          name = kubernetes_secret.cr.metadata[0].name
        }

        container {
          name = "api"
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
              path = "/-/liveness"
              port = 8080
            }
            # initial_delay_seconds = 5
            # period_seconds        = 5
          }

          readiness_probe {
            http_get {
              path = "/-/readiness"
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
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }

          volume_mount {
            mount_path = "/diag"
            name       = "diagvol"
          }

          env {
            name  = "ASPNETCORE_URLS"
            value = "http://+:8080"
          }
          env {
            name  = "DOTNET_DiagnosticPorts"
            value = "/diag/dotnet-monitor.sock"
          }
          env_from {
            secret_ref {
              name     = kubernetes_secret.env.metadata[0].name
              optional = false
            }
          }
        }

        container {
          // https://github.com/dotnet/dotnet-monitor/blob/main/documentation/kubernetes.md#example-deployment
          name  = "monitor"
          image = "mcr.microsoft.com/dotnet/monitor:8"
          args = [
            // https://github.com/dotnet/docs/blob/main/docs/core/diagnostics/dotnet-monitor.md#options-2
            "collect",
            // DO NOT use the --no-auth argument for deployments in production
            // "--no-auth",
          ]
          image_pull_policy = "Always"

          port {
            name           = "collect"
            container_port = 52323
            protocol       = "TCP"
          }

          port {
            name           = "metrics"
            container_port = 52325
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          volume_mount {
            mount_path = "/diag"
            name       = "diagvol"
          }

          env {
            name  = "DOTNETMONITOR_DiagnosticPort__ConnectionMode"
            value = "Listen"
          }
          env {
            name  = "DOTNETMONITOR_Storage__DefaultSharedPath"
            value = "/diag"
          }
          env {
            // ALWAYS use the HTTPS form of the URL for deployments in production
            name  = "DOTNETMONITOR_Urls"
            value = "http://+:52323"
          }
          env {
            // The metrics URL is set in the CMD instruction of the image by default.
            // However, this deployment overrides
            name  = "DOTNETMONITOR_Metrics__Endpoints"
            value = "http://+:52325"
          }
          env {
            // https://github.com/dotnet/dotnet-monitor/blob/main/documentation/configuration/metrics-configuration.md#custom-metrics
            name  = "DOTNETMONITOR_Metrics__Providers__0__ProviderName"
            value = "Microsoft-AspNetCore-Server-Kestrel"
          }
          /* Default to all by not specifying any counter names.
          env {
            name  = "DOTNETMONITOR_Metrics__Providers__0__CounterNames__0"
            value = "connections-per-second"
          }
          env {
            name  = "DOTNETMONITOR_Metrics__Providers__0__CounterNames__1"
            value = "total-connections"
          }
          */
        }

        volume {
          name = "diagvol"

          empty_dir {
          }
        }
      }
    }
  }
}
