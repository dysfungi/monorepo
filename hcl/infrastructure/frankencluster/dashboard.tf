resource "kubernetes_namespace" "k8s_dash" {
  metadata {
    name = "kubernetes-dashboard"
    labels = {
      tier = "prod"
    }
  }
}

# https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard
resource "helm_release" "k8s_dash" {
  name             = "kubernetes-dashboard"
  repository       = "https://kubernetes.github.io/dashboard"
  chart            = "kubernetes-dashboard"
  version          = "7.6.1"
  namespace        = kubernetes_namespace.k8s_dash.metadata[0].name
  create_namespace = false

  set {
    name  = "kong.enabled"
    value = false
  }
}

# https://github.com/kubernetes/dashboard/issues/9066#issuecomment-2126380620
resource "kubernetes_manifest" "k8s_dash_route" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "HTTPRoute"
    "metadata" = {
      "name"      = "kubernetes-dashboard"
      "namespace" = kubernetes_namespace.k8s_dash.metadata[0].name
    }
    "spec" = {
      "parentRefs" = [
        {
          "kind"        = "Gateway"
          "name"        = kubernetes_manifest.prod_gateway.manifest.metadata.name
          "namespace"   = kubernetes_manifest.prod_gateway.manifest.metadata.namespace
          "sectionName" = "https-wildcard.frank.sh"
        }
      ]
      "hostnames" = [
        "k8s.frank.sh",
      ]
      "rules" = [
        {
          "matches" = [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/api/v1/login"
              }
            },
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/api/v1/csrftoken/login"
              }
            },
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/api/v1/me"
              }
            },
          ]
          "backendRefs" = [
            {
              "kind"      = "Service"
              "name"      = "${helm_release.k8s_dash.name}-auth"
              "namespace" = kubernetes_namespace.k8s_dash.metadata[0].name
              "port"      = 8000
            }
          ]
        },
        {
          "matches" = [
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/api"
              }
            },
            {
              "path" = {
                "type"  = "PathPrefix"
                "value" = "/metrics"
              }
            },
          ]
          "backendRefs" = [
            {
              "kind"      = "Service"
              "name"      = "${helm_release.k8s_dash.name}-api"
              "namespace" = kubernetes_namespace.k8s_dash.metadata[0].name
              "port"      = 8000
            }
          ]
        },
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
              "name"      = "${helm_release.k8s_dash.name}-web"
              "namespace" = kubernetes_namespace.k8s_dash.metadata[0].name
              "port"      = 8000
            }
          ]
        }
      ]
    }
  }
}

# https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md#creating-a-service-account
resource "kubernetes_service_account" "k8s_dash_admin" {
  metadata {
    name      = "admin-user"
    namespace = kubernetes_namespace.k8s_dash.metadata[0].name
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding
# https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md#creating-a-clusterrolebinding
resource "kubernetes_cluster_role_binding" "k8s_dash_admin" {
  metadata {
    name = kubernetes_service_account.k8s_dash_admin.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.k8s_dash_admin.metadata[0].name
    namespace = kubernetes_namespace.k8s_dash.metadata[0].name
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret
# https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md#getting-a-long-lived-bearer-token-for-serviceaccount
resource "kubernetes_secret" "k8s_dash_admin_token" {
  metadata {
    name      = kubernetes_service_account.k8s_dash_admin.metadata[0].name
    namespace = kubernetes_namespace.k8s_dash.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.k8s_dash_admin.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}
