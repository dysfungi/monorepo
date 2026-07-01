resource "kubernetes_namespace" "musync" {
  metadata {
    name = "musync"
  }
}
