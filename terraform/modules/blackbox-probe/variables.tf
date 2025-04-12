variable "kubeconfig_path" {
  type     = string
  nullable = false
}

variable "kubernetes_namespace" {
  type     = string
  nullable = false
}

variable "probe_name" {
  type     = string
  nullable = false
}

variable "probe_interval" {
  type     = string
  default  = "30s"
  nullable = false
}
variable "probe_url" {
  type     = string
  nullable = false
}
