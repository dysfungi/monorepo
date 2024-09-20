# https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard
/*
resource "helm_release" "kubernetes_dashboard" {
  name             = "kubernetes-dashboard"
  repository       = "https://kubernetes.github.io/dashboard"
  chart            = "kubernetes-dashboard"
  version          = "7.6.1"
  namespace        = "kubernetes-dashboard"
  create_namespace = true
}
*/
