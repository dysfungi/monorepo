variable "kubeconfig_path" {
  type     = string
  nullable = false
}

variable "kubernetes_namespace" {
  type     = string
  nullable = false
}

variable "app_name" {
  type     = string
  nullable = false
}

variable "service_name" {
  type     = string
  nullable = false
}
