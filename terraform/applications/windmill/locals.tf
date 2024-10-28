locals {
  nodeSelector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "production"
  }
}
