# https://github.com/ecaramba/external-dns/blob/7a52f01ac9ff8dd2d4bb67ec851e5752507e506d/docs/tutorials/vultr.md

# https://artifacthub.io/packages/helm/external-dns/external-dns
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.16.1"
  namespace  = kubernetes_namespace.gateway.metadata[0].name

  values = [
    yamlencode({
      namespaced = false
      provider   = "cloudflare" # NOTE: only "webhook" supports more config like resources
      affinity   = local.affinity
      resources = {
        requests = {
          cpu    = "5m"
          memory = "32Mi"
        }
        limits = {
          cpu    = "10m"
          memory = "64Mi"
        }
      }
      rbac = {
        create = true
      }
      sources = [
        "gateway-grpcroute",
        "gateway-httproute",
        # "gateway-tcproute",
        # "gateway-tlsroute",
        # "gateway-udproute",
        # "ingress",
        "service",
      ]
      env = [
        {
          name = "CF_API_TOKEN"
          valueFrom = {
            secretKeyRef = {
              key      = "apiToken"
              name     = kubernetes_secret.cloudflare.metadata[0].name
              optional = false
            }
          }
        }
      ]
      serviceMonitor = {
        enabled = true
      }
    })
  ]
}
