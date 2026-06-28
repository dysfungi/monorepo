# The grafana-cloud Secret is sourced from 1Password by the External Secrets
# Operator. We apply the ExternalSecret custom-resource instance through the kbst
# kustomization provider (data.kustomization_overlay -> kustomization_resource),
# mirroring the external-secrets module's cluster_secret_store.tf. We deliberately
# do NOT use kubernetes_manifest: it performs a server-side dry-run at PLAN time,
# which fails when the external-secrets.io CRDs are not reachable. The CRDs are
# installed by the external-secrets stack (a CI `needs:` dependency), but
# kustomization_resource defers reconciliation to apply time, keeping plans
# robust against CRD availability.
data "kustomization_overlay" "grafana_cloud_external_secret" {
  resources = ["${path.module}/external_secret_grafana_cloud.yaml"]
}

resource "kustomization_resource" "grafana_cloud_external_secret" {
  for_each = data.kustomization_overlay.grafana_cloud_external_secret.ids
  manifest = data.kustomization_overlay.grafana_cloud_external_secret.manifests[each.value]
}
