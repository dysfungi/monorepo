locals {
  hostname = "${var.subdomain}.${var.root_domain}"
  probe    = "http://${local.hostname}/ip"
}
