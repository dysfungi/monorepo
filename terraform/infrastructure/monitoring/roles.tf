resource "kubernetes_role" "kube_prom_operator_secret_reader" {
  metadata {
    name      = "${helm_release.kube_prometheus.name}-operator:secret-reader"
    namespace = helm_release.kube_prometheus.namespace
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    resource_names = [
      kubernetes_secret.prom_secrets.metadata[0].name,
      kubernetes_secret.alertmanager_env.metadata[0].name,
    ]
    verbs = ["get", "watch"]
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding
resource "kubernetes_role_binding" "kube_prom_secret_reader" {
  metadata {
    name      = kubernetes_role.kube_prom_operator_secret_reader.metadata[0].name
    namespace = kubernetes_role.kube_prom_operator_secret_reader.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.kube_prom_operator_secret_reader.metadata[0].name
  }
  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = "${helm_release.kube_prometheus.name}-operator"
    namespace = helm_release.kube_prometheus.namespace
  }
}
