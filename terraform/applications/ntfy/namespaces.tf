resource "kubernetes_namespace" "ntfy" {
  metadata {
    name = "ntfy"
  }
}
