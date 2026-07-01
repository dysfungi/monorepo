# Syncs the Anthropic API key from 1Password into the "frankenbot-anthropic"
# Secret via ESO. Same kbst kustomization pattern and ordering rationale as
# external_secret_github_app.tf.
#
# PHASE 0 (USER ACTION) — create this 1Password item in the Frankenstructure
# vault before the first deploy:
#   Item "Frankenbot Anthropic" with field:
#     - api-key
data "kustomization_overlay" "anthropic" {
  resources = ["${path.module}/external_secret_anthropic.yaml"]
}

resource "kustomization_resource" "anthropic" {
  for_each = data.kustomization_overlay.anthropic.ids
  manifest = data.kustomization_overlay.anthropic.manifests[each.value]

  depends_on = [kubernetes_namespace.frankenbot]
}
