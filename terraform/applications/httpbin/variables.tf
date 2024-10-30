variable "kubeconfig_path" {
  type = string
}

variable "root_domain" {
  type    = string
  default = "frank.sh"
}

variable "subdomain" {
  type    = string
  default = "httpbin"
}
