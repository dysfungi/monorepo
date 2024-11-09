variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "home_ip" {
  type    = string
  default = "98.147.146.93"
}

variable "vultr_api_key" {
  type      = string
  sensitive = true
}
