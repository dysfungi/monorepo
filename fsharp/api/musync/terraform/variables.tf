variable "app_version" {
  type = string
}

variable "dockerconfigjson" {
  type      = string
  sensitive = true
}

variable "kubeconfig_path" {
  type     = string
  nullable = false
}

variable "vultr_api_key" {
  type      = string
  nullable  = false
  sensitive = true
}
