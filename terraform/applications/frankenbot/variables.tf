variable "app_version" {
  type        = string
  description = "Container image tag for the frankenbot agent (dispatch + triage share one image)."
}

variable "dockerconfigjson" {
  type        = string
  sensitive   = true
  description = "Vultr Container Registry pull credentials (.dockerconfigjson)."
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to the kubeconfig the kubernetes/kustomization providers authenticate with."
}

variable "enabled" {
  type        = bool
  default     = true
  description = "Global kill switch -> FRANKENBOT_ENABLED. When false the dispatcher exits 0 without spawning triage Jobs."
}

variable "max_concurrent_jobs" {
  type        = number
  default     = 1
  description = "Cap on simultaneously-active triage Jobs -> FRANKENBOT_MAX_CONCURRENT_JOBS."
}

variable "frankenbot_postgres_password" {
  type        = string
  sensitive   = true
  description = "Password for the frankenbot login role on the shared Vultr managed Postgres (databases.tf)."
}

variable "vultr_api_key" {
  type        = string
  sensitive   = true
  description = "Vultr API key for the vultr provider (reads the managed Postgres instance, provisions the DB + user)."
}
