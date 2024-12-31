locals {
  hostname  = "${var.subdomain}.${var.root_domain}"
  probe     = "http://${local.hostname}/-/liveness"
  dbsslmode = "require"
  labels = {
    "app.kubernetes.io/name"     = "automate"
    "app.kubernetes.io/instance" = "automate-api"
  }
  dbmigrate_labels = merge(local.labels, {
    "app.kubernetes.io/instance" = "dbmigrate"
  })
  affinity = {}
  node_selector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "default"
  }
}
