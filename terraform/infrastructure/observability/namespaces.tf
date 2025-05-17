resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}
