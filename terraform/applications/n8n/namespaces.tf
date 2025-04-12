resource "kubernetes_namespace" "n8n" {
  metadata {
    name = "n8n"
  }
}
