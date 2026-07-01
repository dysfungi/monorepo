resource "kubernetes_secret" "cr" {
  // https://docs.vultr.com/how-to-use-vultr-container-registry-with-kubernetes#generate-the-vultr-container-registry-kubernetes-credentials
  metadata {
    name      = "vultr-cr-credentials"
    namespace = local.namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.dockerconfigjson
  }
}
