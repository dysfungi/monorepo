# https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-kube-stack
resource "helm_release" "opentelemetry_kube_stack" {
  name             = "opentelemetry-kube-stack"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-kube-stack"
  version          = "0.5.3"
  namespace        = local.namespace
  create_namespace = false

  values = [
    yamlencode({
      defaultCRConfig = {
        affinity = local.affinity
      }
    }),
  ]
}
