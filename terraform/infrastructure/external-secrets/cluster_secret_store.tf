# The repo applies single custom-resource INSTANCES through the kbst
# kustomization provider (data.kustomization_overlay -> kustomization_resource),
# the same provider gateway/crds.tf uses for raw manifests. We deliberately do
# NOT use kubernetes_manifest here: it performs a server-side dry-run at PLAN
# time, which fails when the target CRD is not yet installed -- and the
# external-secrets.io CRDs are created by the ESO Helm release in this same
# apply. kustomization_resource defers reconciliation to apply time and honours
# depends_on, so the ClusterSecretStore can be planned before its CRD exists.
data "kustomization_overlay" "cluster_secret_store" {
  resources = ["${path.module}/cluster_secret_store.yaml"]
}

resource "kustomization_resource" "cluster_secret_store" {
  for_each = data.kustomization_overlay.cluster_secret_store.ids
  manifest = data.kustomization_overlay.cluster_secret_store.manifests[each.value]

  # The onepassword (Connect) provider only authenticates once the Connect server
  # is reachable, so swap the ClusterSecretStore to it only after Connect deploys.
  depends_on = [
    helm_release.external_secrets,
    helm_release.onepassword_connect,
  ]
}
