# Applies the automate-onepassword ExternalSecret instance through the kbst
# kustomization provider (data.kustomization_overlay -> kustomization_resource),
# mirroring terraform/infrastructure/external-secrets/cluster_secret_store.tf.
# We deliberately do NOT use kubernetes_manifest: it performs a server-side
# dry-run at PLAN time against the external-secrets.io CRDs, which couples this
# stack's plan to live cluster CRD state. kustomization_resource defers
# reconciliation to apply time.
#
# Ordering: the ESO CRDs and ClusterSecretStore "onepassword" are installed by
# the external-secrets stack, which the cicd deploy-automate-api job depends on
# transitively (deploy-automate-api -> deployed-foundation -> deploy-external-secrets),
# so the CRD and store exist before this resource reconciles.
data "kustomization_overlay" "external_secret_automate" {
  resources = ["${path.module}/external_secret_automate.yaml"]
}

resource "kustomization_resource" "external_secret_automate" {
  for_each = data.kustomization_overlay.external_secret_automate.ids
  manifest = data.kustomization_overlay.external_secret_automate.manifests[each.value]

  depends_on = [kubernetes_namespace.automate]
}
