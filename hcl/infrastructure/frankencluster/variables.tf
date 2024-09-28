variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "email" {
  type    = string
  default = "derek@frank.sh"
}

variable "github_username" {
  type = string
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "kubeconfig" {
  type = string
}

variable "vultr_api_key" {
  type      = string
  sensitive = true
}
