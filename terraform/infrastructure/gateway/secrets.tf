# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/cloudflare.md#using-helm
# https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/#api-tokens
resource "kubernetes_secret" "cloudflare" {
  metadata {
    name      = "cloudflare"
    namespace = local.namespace
  }
  data = {
    apiToken = var.cloudflare_api_token
  }
}
