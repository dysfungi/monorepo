locals {
  namespace = one(kubernetes_namespace.namespace.metadata).name
}
