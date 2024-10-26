# https://github.com/ecaramba/external-dns/blob/7a52f01ac9ff8dd2d4bb67ec851e5752507e506d/docs/tutorials/vultr.md

# https://artifacthub.io/packages/helm/external-dns/external-dns
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.15.0"
  namespace  = kubernetes_namespace.gateway.metadata[0].name

  values = [
    yamlencode({
      "namespaced"   = false
      "provider"     = "cloudflare"
      "nodeSelector" = local.nodeSelector
      "rbac" = {
        "create" = true
      }
      "env" = [
        {
          "name" = "CF_API_TOKEN"
          "valueFrom" = {
            "secretKeyRef" = {
              "key"      = "apiToken"
              "name"     = kubernetes_secret.cloudflare.metadata[0].name
              "optional" = false
            }
          }
        }
      ]
    })
  ]
}
