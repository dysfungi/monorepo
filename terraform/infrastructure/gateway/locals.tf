locals {
  nodeSelector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = kubernetes_namespace.gateway.metadata[0].name
  }
}
