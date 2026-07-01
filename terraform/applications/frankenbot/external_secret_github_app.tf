# Syncs the Frankenbot GitHub App credentials from 1Password into the
# "frankenbot-github-app" Secret via ESO, applied through the kbst kustomization
# provider (data.kustomization_overlay -> kustomization_resource), mirroring
# fsharp/api/automate/terraform/external_secret_automate.tf.
#
# We deliberately do NOT use kubernetes_manifest: it performs a server-side
# dry-run at PLAN time against the external-secrets.io CRDs, coupling this stack's
# plan to live cluster CRD state. kustomization_resource defers reconciliation to
# apply time.
#
# Ordering: the ESO CRDs and the ClusterSecretStore "onepassword" are installed
# by the external-secrets stack, which the cicd deploy-frankenbot job depends on
# transitively (deploy-frankenbot -> deployed-foundation -> deploy-external-secrets),
# so the CRD and store exist before this resource reconciles.
#
# PHASE 0 (USER ACTION) — create this 1Password item in the Frankenstructure
# vault before the first deploy:
#   Item "Frankenbot GitHub App" with fields:
#     - app-id
#     - installation-id
#     - private-key   (unencrypted RSA PEM)
data "kustomization_overlay" "github_app" {
  resources = ["${path.module}/external_secret_github_app.yaml"]
}

resource "kustomization_resource" "github_app" {
  for_each = data.kustomization_overlay.github_app.ids
  manifest = data.kustomization_overlay.github_app.manifests[each.value]

  depends_on = [kubernetes_namespace.frankenbot]
}
