# https://cert-manager.io/docs/installation/helm/
# https://artifacthub.io/packages/helm/cert-manager/cert-manager
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.1"
  namespace  = kubernetes_namespace.gateway.metadata[0].name

  values = [
    yamlencode({
      affinity = local.affinity
      crds = {
        enabled = true
        keep    = true
      }
      cainjector = {
        affinity = local.affinity
      }
      startupapicheck = {
        affinity = local.affinity
      }
      webhook = {
        affinity = local.affinity
      }
      # https://cert-manager.io/docs/configuration/acme/dns01/#setting-nameservers-for-dns01-self-check
      extraArgs = [
        # Since Terraform Utilizes HCL as well as Helm using the Helm Template Language,
        # it's necessary to escape the `{}`, `[]`, `.`, and `,` characters twice in order
        # for it to be parsed.
        # https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release#example-usage---chart-repository-configured-outside-of-terraform
        "--dns01-recursive-nameservers-only",
        "--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53",
        # https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/integrating-cert-manager/#deploy-cert-manager
        "--feature-gates=ExperimentalGatewayAPISupport=true",
      ]
      prometheus = {
        servicemonitor = {
          enabled = true
        }
      }
    }),
  ]
}
