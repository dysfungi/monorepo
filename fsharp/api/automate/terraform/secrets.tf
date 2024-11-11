resource "kubernetes_secret" "cr" {
  // https://docs.vultr.com/how-to-use-vultr-container-registry-with-kubernetes#generate-the-vultr-container-registry-kubernetes-credentials
  metadata {
    name      = "vultr-cr-credentials"
    namespace = kubernetes_namespace.automate.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.dockerconfigjson
  }
}
