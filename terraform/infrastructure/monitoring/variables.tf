variable "alertmanager_subdomain" {
  type    = string
  default = "alertmanager"
}

variable "discord_webhook_alerts" {
  type      = string
  sensitive = true
}

variable "email" {
  type      = string
  sensitive = true
  default   = "derek@frank.sh"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "grafana_subdomain" {
  type    = string
  default = "grafana"
}

variable "healthchecksio_api_key" {
  type      = string
  sensitive = true
}

variable "kubeconfig_path" {
  type = string
}

variable "prometheus_subdomain" {
  type    = string
  default = "prometheus"
}

variable "root_domain" {
  type    = string
  default = "frank.sh"
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

variable "todoist_email" {
  type      = string
  sensitive = true
}
