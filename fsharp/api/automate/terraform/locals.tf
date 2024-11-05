locals {
  hostname = "${var.subdomain}.${var.root_domain}"
  probe    = "http://${local.hostname}/-/alive"
  labels = {
    "app.kubernetes.io/name"     = "automate"
    "app.kubernetes.io/instance" = "automate-api"
  }
  affinity = {}
  node_selector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "default"
  }
}
