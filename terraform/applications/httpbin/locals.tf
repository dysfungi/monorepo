locals {
  namespace = kubernetes_namespace.httpbin.metadata[0].name
}
