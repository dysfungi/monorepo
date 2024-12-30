variable "app_version" {
  type = string
}

variable "automate_dropbox_client_id" {
  type      = string
  sensitive = true
}

variable "automate_dropbox_client_secret" {
  type      = string
  sensitive = true
}

variable "automate_postgres_password" {
  type      = string
  sensitive = true
}

variable "automate_todoist_client_id" {
  type      = string
  sensitive = true
}

variable "automate_todoist_client_secret" {
  type      = string
  sensitive = true
}

variable "automate_todoist_verification_token" {
  type      = string
  sensitive = true
}

variable "dockerconfigjson" {
  type      = string
  sensitive = true
}

variable "github_username" {
  type = string
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "kubeconfig_path" {
  type = string
}

variable "root_domain" {
  type    = string
  default = "frank.sh"
}

variable "subdomain" {
  type    = string
  default = "api"
}

variable "vultr_api_key" {
  type      = string
  sensitive = true
}
