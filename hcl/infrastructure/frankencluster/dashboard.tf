resource "kubernetes_namespace" "k8s_dashboard" {
  metadata {
    name = "kubernetes-dashboard"
    labels = {
      tier = "prod"
    }
  }
}

# https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard
resource "helm_release" "k8s_dashboard" {
  name             = "kubernetes-dashboard"
  repository       = "https://kubernetes.github.io/dashboard"
  chart            = "kubernetes-dashboard"
  version          = "7.6.1"
  namespace        = kubernetes_namespace.k8s_dashboard.metadata[0].name
  create_namespace = false
}

resource "kubernetes_manifest" "k8s_dashboard_web_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "kubernetes-dashboard-web-route"
      "namespace" = kubernetes_namespace.k8s_dashboard.metadata[0].name
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          "sectionName" = "https"
        }
      ]
      "hostnames" = [
        "k8s.api.frank.sh",
        "k8s.frank.sh",
      ]
      "rules" = [
        {
          "matches" = [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/"
              }
            }
          ]
          "backendRefs" = [
            {
              "kind"      = "Service"
              "name"      = "${helm_release.k8s_dashboard.name}-web"
              "namespace" = kubernetes_namespace.k8s_dashboard.metadata[0].name
              "port"      = 8000
            }
          ]
        }
      ]
    }
  }
}
