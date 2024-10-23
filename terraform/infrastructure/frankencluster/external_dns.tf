# https://github.com/ecaramba/external-dns/blob/7a52f01ac9ff8dd2d4bb67ec851e5752507e506d/docs/tutorials/vultr.md
resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
  }
}

# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/cloudflare.md#using-helm
resource "kubernetes_secret" "external_dns_cloudflare_creds" {
  metadata {
    name      = "external-dns-cloudflare-credentials"
    namespace = kubernetes_namespace.external_dns.metadata[0].name
  }
  data = {
    apiToken = var.cloudflare_api_token
  }
}

# https://artifacthub.io/packages/helm/external-dns/external-dns
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.15.0"
  namespace  = kubernetes_namespace.external_dns.metadata[0].name

  set {
    name  = "namespaced"
    value = false
  }

  set {
    name  = "provider"
    value = "cloudflare"
  }

  values = [
    yamlencode({
      "env" = [
        {
          "name" = "CF_API_TOKEN"
          "valueFrom" = {
            "secretKeyRef" = {
              "key"      = "apiToken"
              "name"     = kubernetes_secret.external_dns_cloudflare_creds.metadata[0].name
              "optional" = false
            }
          }
        }
      ]
      "nodeSelector" = local.foundationNodeSelector
    })
  ]

  set {
    name  = "rbac.create"
    value = true
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role
resource "kubernetes_role" "external_dns_secret_reader" {
  metadata {
    name      = "${helm_release.external_dns.name}:secret-reader"
    namespace = helm_release.external_dns.namespace
  }
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [kubernetes_secret.external_dns_cloudflare_creds.metadata[0].name]
    verbs          = ["get", "watch"]
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding
resource "kubernetes_role_binding" "external_dns_secret_reader" {
  metadata {
    name      = kubernetes_role.external_dns_secret_reader.metadata[0].name
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.external_dns_secret_reader.metadata[0].name
  }
  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = helm_release.external_dns.name
    namespace = helm_release.external_dns.namespace
  }
}
