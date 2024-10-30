resource "kubernetes_namespace" "httpbin" {
  metadata {
    name = "httpbin"
  }
}
