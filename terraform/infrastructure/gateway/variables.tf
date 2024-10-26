variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "email" {
  type      = string
  sensitive = true
  default   = "derek@frank.sh"
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "github_username" {
  type = string
}

variable "kubeconfig_path" {
  type = string
}
