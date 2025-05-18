# https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-kube-stack
resource "helm_release" "opentelemetry_kube_stack" {
  name             = "opentelemetry-kube-stack"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-kube-stack"
  version          = "0.5.3"
  namespace        = local.namespace
  create_namespace = false

  # https://github.com/open-telemetry/opentelemetry-operator/blob/main/README.md
  # https://github.com/open-telemetry/opentelemetry-operator/blob/main/docs/api/README.md
  # https://docs.honeycomb.io/send-data/kubernetes/opentelemetry/create-telemetry-pipeline/
  values = [
    yamlencode({
      clusterName     = "frank8s"
      defaultCRConfig = local.base_collector
      collectors      = local.collectors
      instrumentation = local.instrumentation
      extraEnvs = [
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
