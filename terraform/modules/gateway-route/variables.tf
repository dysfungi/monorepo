variable "kubeconfig_path" {
  type     = string
  nullable = false
}

variable "kubernetes_namespace" {
  type     = string
  nullable = false
}

variable "service_name" {
  type     = string
  nullable = false
}

variable "service_port" {
  type     = number
  nullable = false
}

variable "subdomain" {
  type     = string
  nullable = false
}
