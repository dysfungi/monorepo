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
