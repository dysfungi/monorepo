locals {
  namespace         = one(kubernetes_namespace.gateway.metadata).name
  ngf_chart_version = "2.0.1"
}
