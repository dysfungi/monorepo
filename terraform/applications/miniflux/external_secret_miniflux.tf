# Applies the miniflux-admin ExternalSecret instance through the kbst
# kustomization provider (data.kustomization_overlay -> kustomization_resource),
# mirroring terraform/infrastructure/external-secrets/cluster_secret_store.tf and
# fsharp/api/automate/terraform/external_secret_automate.tf. We deliberately do
# NOT use kubernetes_manifest: it performs a server-side dry-run at PLAN time
# against the external-secrets.io CRDs, which couples this stack's plan to live
# cluster CRD state. kustomization_resource defers reconciliation to apply time.
#
# Ordering: the ESO CRDs and ClusterSecretStore "onepassword" are installed by
# the external-secrets stack, which the cicd deploy-miniflux job depends on
# transitively (deploy-miniflux -> deployed-foundation -> deploy-external-secrets),
# so the CRD and store exist before this resource reconciles. The helm_release
# below depends on this resource so the ExternalSecret is applied (and ESO has
# created the miniflux-admin Secret) before the pods reference it.
data "kustomization_overlay" "external_secret_miniflux" {
  resources = ["${path.module}/external_secret_miniflux.yaml"]
}

resource "kustomization_resource" "external_secret_miniflux" {
  for_each = data.kustomization_overlay.external_secret_miniflux.ids
  manifest = data.kustomization_overlay.external_secret_miniflux.manifests[each.value]

  depends_on = [kubernetes_namespace.namespace]
}
