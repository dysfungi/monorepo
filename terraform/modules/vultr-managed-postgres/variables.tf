variable "kubernetes_namespace" {
  type     = string
  nullable = false
}

variable "kubeconfig_path" {
  type     = string
  nullable = false
}

variable "vultr_api_key" {
  type      = string
  nullable  = false
  sensitive = true
}

variable "app_name" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.app_name))
    error_message = "The app_name must be simple by using only lowercase characters, numbers, and underscores."
  }
}
variable "app_dbname" {
  type     = string
  nullable = false
}

variable "app_username" {
  type     = string
  nullable = false
}

variable "app_password" {
  type      = string
  nullable  = false
  sensitive = true
}

variable "connection_pool_mode" {
  type     = string
  default  = "transaction"
  nullable = false
}

variable "connection_pool_size" {
  type     = number
  default  = 5
  nullable = false

  validation {
    condition     = var.connection_pool_size == parseint(tostring(var.connection_pool_size), 10)
    error_message = "The connection pool size must be an integer."
  }
}

variable "sslmode" {
  type        = string
  description = "https://www.postgresql.org/docs/current/libpq-ssl.html#LIBPQ-SSL-PROTECTION"
  default     = "require"
  nullable    = false

  validation {
    # Vultr pg does not support unsafe sslmode like "prefer".
    condition     = contains(["require", "verify-ca", "verify-full"], var.sslmode)
    error_message = "The SSL mode must be valid"
  }
}
