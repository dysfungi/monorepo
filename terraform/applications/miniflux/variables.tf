variable "github_token" {
  type      = string
  sensitive = true
}

variable "github_username" {
  type = string
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

variable "miniflux_admin_username" {
  type     = string
  nullable = false
}

variable "miniflux_admin_password" {
  type      = string
  nullable  = false
  sensitive = true
}

variable "miniflux_postgres_password" {
  type      = string
  nullable  = false
  sensitive = true
}
