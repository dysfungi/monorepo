resource "kubernetes_namespace" "frankenbot" {
  metadata {
    name = "frankenbot"
  }
}
