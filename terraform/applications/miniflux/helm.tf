# https://artifacthub.io/packages/helm/gabe565/miniflux
resource "helm_release" "miniflux" {
  name       = "miniflux"
  repository = "oci://ghcr.io/gabe565/charts"
  chart      = "miniflux"
  version    = "0.9.2"
  namespace  = local.namespace

  values = [
    yamlencode({
      # https://artifacthub.io/packages/helm/gabe565/miniflux?modal=values
      # https://github.com/bjw-s/helm-charts/blob/a081de5/charts/library/common/values.yaml
      controller = {
        replicas = 2
      }
      env = {
        DATABASE_URL   = module.postgres.app.url
        CREATE_ADMIN   = "1"
        ADMIN_USERNAME = var.miniflux_admin_username
        ADMIN_PASSWORD = var.miniflux_admin_password
      }
      postgresql = {
        enabled = false
      }
      serviceMonitor = {
        main = {
          enabled         = true
          allowedNetworks = "10.0.0.0/8"
        }
      }
      nodeSelector = {
        "kubernetes.io/os"        = "linux"
        "vke.vultr.com/node-pool" = "default"
      }
      resources = {
        limits = {
          cpu    = "0.5"
          memory = "1Gi"
        }
        requests = {
          cpu    = "0.1"
          memory = "0.5Gi"
        }
      }
    }),
  ]
}
