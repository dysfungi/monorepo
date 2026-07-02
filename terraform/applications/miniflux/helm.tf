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
        # bjw-s common renders `controller.annotations` onto the Deployment
        # (workload) metadata — exactly where Stakater Reloader looks (pod
        # annotations are ignored by Reloader). This makes the Deployment restart
        # when ESO rotates the miniflux-admin Secret referenced via env
        # valueFrom.secretKeyRef. Rotation value is modest (admin is created once
        # at first boot via CREATE_ADMIN), but the annotation is clean, harmless,
        # and keeps every ESO-backed workload consistently Reloader-managed.
        annotations = {
          "reloader.stakater.com/auto" = "true"
        }
      }
      env = {
        DATABASE_URL = module.postgres.app.url
        CREATE_ADMIN = "1"
        # ADMIN_USERNAME/ADMIN_PASSWORD are sourced from 1Password by ESO and
        # exposed via the miniflux-admin Secret (see external_secret_miniflux.tf).
        # The bjw-s common library passes env map entries through verbatim, so a
        # valueFrom.secretKeyRef object renders as a secret-backed container env
        # var instead of a plaintext value in the pod spec.
        ADMIN_USERNAME = {
          valueFrom = {
            secretKeyRef = {
              name = "miniflux-admin"
              key  = "ADMIN_USERNAME"
            }
          }
        }
        ADMIN_PASSWORD = {
          valueFrom = {
            secretKeyRef = {
              name = "miniflux-admin"
              key  = "ADMIN_PASSWORD"
            }
          }
        }
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
      # Lean profile (see docs/right-sizing-resources.md). This was the fleet's worst
      # over-provisioner: requested 0.5Gi/0.1 CPU but 7-day actuals sit near idle.
      # Trimmed to a tight floor; CPU limit dropped (throttling hurts latency).
      resources = {
        requests = {
          cpu    = "10m"
          memory = "64Mi"
        }
        limits = {
          memory = "64Mi"
        }
      }
    }),
  ]

  # Ensure the miniflux-admin ExternalSecret is applied (and ESO has materialized
  # the backing Secret) before the pods reference it via env valueFrom.secretKeyRef.
  depends_on = [kustomization_resource.external_secret_miniflux]
}
