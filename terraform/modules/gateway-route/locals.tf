locals {
  hostnames = kubernetes_manifest.route.manifest.spec.hostnames
}
