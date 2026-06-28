variable "kubeconfig_path" {
  type = string
}

# Secret-zero: the read-only 1Password service-account token used by ESO's
# onepasswordSDK ClusterSecretStore. Injected via CI (deferred wiring); reuses
# the existing read-only OP service-account token.
variable "op_service_account_token" {
  type      = string
  sensitive = true
}

# 1Password Connect bootstrap credentials: the raw contents of the
# 1password-credentials.json file produced by `op connect server create`. Held
# as the RAW JSON string (NOT base64) -- kubernetes_secret.data base64-encodes
# transparently, and the chart mounts it as a file the Connect server reads as
# raw JSON. Injected via CI.
variable "op_connect_credentials_json" {
  type      = string
  sensitive = true
}

# 1Password Connect access token: the token ESO presents to the Connect server
# (connectTokenSecretRef). Produced by `op connect token create`. Injected via CI.
variable "op_connect_token" {
  type      = string
  sensitive = true
}
