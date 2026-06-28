# Secret-zero: the read-only 1Password service-account token that ESO's
# onepasswordSDK ClusterSecretStore uses to authenticate to 1Password. This is
# the one secret that cannot itself be sourced through ESO (chicken-and-egg), so
# it is injected directly (via CI) and bootstraps every other secret in the
# cluster.
resource "kubernetes_secret" "onepassword_sdk_token" {
  metadata {
    name      = "onepassword-sdk-token"
    namespace = local.namespace
  }
  type = "Opaque"
  data = {
    token = var.op_service_account_token
  }

  depends_on = [kubernetes_namespace.external_secrets]
}
