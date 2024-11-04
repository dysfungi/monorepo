resource "kubernetes_namespace" "automate" {
  metadata {
    name = "automate"
  }
}
