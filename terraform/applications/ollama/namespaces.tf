resource "kubernetes_namespace" "ollama" {
  metadata {
    name = "ollama"
  }
}
