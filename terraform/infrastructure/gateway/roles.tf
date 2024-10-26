# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role
# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#deploying-a-clusterissuer
resource "kubernetes_role" "secret_reader" {
  metadata {
    name      = "secret-reader"
    namespace = kubernetes_namespace.gateway.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    resource_names = [
      kubernetes_secret.cloudflare.metadata[0].name,
    ]
    verbs = ["get", "watch"]
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding
# https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr#deploying-a-clusterissuer
resource "kubernetes_role_binding" "cert_manager_secret_reader" {
  metadata {
    name      = "cert-manager-${kubernetes_role.secret_reader.metadata[0].name}"
    namespace = kubernetes_role.secret_reader.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.secret_reader.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = helm_release.cert_manager.name
    namespace = helm_release.cert_manager.namespace
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding
resource "kubernetes_role_binding" "external_dns_secret_reader" {
  metadata {
    name      = "external-dns-${kubernetes_role.secret_reader.metadata[0].name}"
    namespace = kubernetes_role.secret_reader.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.secret_reader.metadata[0].name
  }
  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = helm_release.external_dns.name
    namespace = helm_release.external_dns.namespace
  }
}
