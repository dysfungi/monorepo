resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = local.namespace
  }
}
