resource "kubernetes_namespace" "windmill" {
  metadata {
    name = "windmill"
  }
}
