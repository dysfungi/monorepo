variable "healthchecksio_api_key" {
  type      = string
  sensitive = true
}

variable "honeycomb_key_id" {
  type      = string
  sensitive = true
}

variable "honeycomb_key_secret" {
  type      = string
  sensitive = true
}

variable "honeycomb_api_key" {
  type        = string
  sensitive   = true
  description = "Honeycomb v1 Configuration API key (for triggers/recipients)"
}

variable "kubeconfig_path" {
  type = string
}
