variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "home_ip" {
  type    = string
  default = "146.70.183.149"
}

variable "vultr_api_key" {
  type      = string
  sensitive = true
}
