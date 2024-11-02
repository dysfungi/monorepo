resource "helm_release" "httpbin" {
  name       = "httpbin"
  repository = "https://matheusfm.dev/charts"
  chart      = "httpbin"
  version    = "0.1.1"
  namespace  = kubernetes_namespace.httpbin.metadata[0].name

  values = [
    yamlencode({
      "replicaCount" = "2"
      "nodeSelector" = {
        "kubernetes.io/os"        = "linux"
        "vke.vultr.com/node-pool" = "default"
      }
    }),
  ]
}
