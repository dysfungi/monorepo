variable "grafana_cloud_instance_id" {
  type      = string
  sensitive = true
}

variable "grafana_cloud_api_key" {
  type      = string
  sensitive = true
}

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

variable "kubeconfig_path" {
  type = string
}
