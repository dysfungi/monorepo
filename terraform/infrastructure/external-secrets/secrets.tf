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

# 1Password Connect credentials file, consumed by the connect-helm chart via
# connect.credentialsName. The data key MUST match the chart's connect.credentialsKey
# ("1password-credentials.json"); the chart mounts this key as the file the Connect
# server reads. Store the RAW JSON -- kubernetes_secret.data base64-encodes it, and
# k8s decodes back to raw JSON on mount (do NOT pre-base64 the value).
resource "kubernetes_secret" "onepassword_connect_credentials" {
  metadata {
    name      = "onepassword-connect-credentials"
    namespace = local.namespace
  }
  type = "Opaque"
  data = {
    "1password-credentials.json" = var.op_connect_credentials_json
  }

  depends_on = [kubernetes_namespace.external_secrets]
}

# 1Password Connect access token. ESO's onepassword (Connect) ClusterSecretStore
# authenticates to the Connect server with this token via connectTokenSecretRef
# (key "token").
resource "kubernetes_secret" "onepassword_connect_token" {
  metadata {
    name      = "onepassword-connect-token"
    namespace = local.namespace
  }
  type = "Opaque"
  data = {
    token = var.op_connect_token
  }

  depends_on = [kubernetes_namespace.external_secrets]
}
