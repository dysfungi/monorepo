variable "kubeconfig_path" {
  type     = string
  nullable = false
}

variable "kubernetes_namespace" {
  type     = string
  nullable = false
}

variable "root_domain" {
  type     = string
  nullable = false
  default  = "frank.sh"
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

variable "trace_sampling" {
  type     = number
  nullable = false
  default  = 100
}

variable "upstream_read_timeout" {
  type     = string
  nullable = true
  default  = null

  # When null (default) no SnippetsFilter is emitted and NGF's default ~60s
  # proxy_read_timeout applies -- preserves existing callers (miniflux/httpbin).
  # Set to an nginx time value ("1h", "24h") or "0" (disable) for apps with
  # long-lived SSE/WebSocket streams (e.g. ntfy).
  #
  # WHY a SnippetsFilter and not spec.rules[].timeouts: NGF ignores the native
  # Gateway-API HTTPRoute timeouts field (silent no-op), so proxy_read_timeout via
  # a SnippetsFilter is the only mechanism that actually takes effect.
  # https://docs.nginx.com/nginx-gateway-fabric/overview/gateway-api-compatibility/
}
