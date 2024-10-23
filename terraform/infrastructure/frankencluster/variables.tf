variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "discord_webhook_alerts" {
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

variable "kubeconfig_path" {
  type = string
}

variable "smtp_password" {
  type      = string
  sensitive = true
}

variable "smtp_port" {
  type = number
}

variable "smtp_server" {
  type = string
}

variable "smtp_username" {
  type = string
}
