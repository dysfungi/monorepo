# https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-kube-stack
resource "helm_release" "opentelemetry_kube_stack" {
  name             = "opentelemetry-kube-stack"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-kube-stack"
  version          = "0.6.1"
  namespace        = local.namespace
  create_namespace = false

  # https://github.com/open-telemetry/opentelemetry-operator/blob/main/README.md
  # https://github.com/open-telemetry/opentelemetry-operator/blob/main/docs/api/README.md
  # https://docs.honeycomb.io/send-data/kubernetes/opentelemetry/create-telemetry-pipeline/
  values = [
    yamlencode({
      clusterName     = "frank8s"
      defaultCRConfig = local.base_collector
      collectors = {
        cluster = local.cluster_collector
        daemon  = local.daemon_collector
      }
      instrumentation = local.instrumentation
      opentelemetry-operator = {
        enabled  = true
        affinity = local.affinity
        pdb = {
          create = true
        }
        manager = {
          image = {
            # tag = "0.125.0"
          }
          collectorImage = {
            # repository = "otel/opentelemetry-collector"
            # tag        = "0.126.0"
          }
        }
      }
      extraEnvs = [
        {
          name = "GRAFANA_CLOUD_API_KEY"
          valueFrom = {
            secretKeyRef = {
              name     = "grafana-cloud"
              key      = "api-key"
              optional = false
            }
          }
        },
        {
          name = "GRAFANA_CLOUD_INSTANCE_ID"
          valueFrom = {
            secretKeyRef = {
              name     = "grafana-cloud"
              key      = "instance-id"
              optional = false
            }
          }
        },
        {
          name = "HONEYCOMB_API_KEY"
          valueFrom = {
            secretKeyRef = {
              name     = "honeycomb"
              key      = "api-key"
              optional = false
            }
          }
        },
      ]
    }),
  ]
}
