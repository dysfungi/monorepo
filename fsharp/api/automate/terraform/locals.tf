locals {
  namespace = one(kubernetes_namespace.automate.metadata).name
  dbsslmode = "require"
  labels = {
    "app.kubernetes.io/name"     = "automate"
    "app.kubernetes.io/instance" = "automate-api"
  }
  node_selector = {
    "kubernetes.io/os" = "linux"
  }
}
