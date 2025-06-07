resource "kubernetes_secret" "grafana_cloud" {
  metadata {
    name      = "grafana-cloud"
    namespace = local.namespace
  }

  data = {
    api-key     = var.grafana_cloud_api_key
    instance-id = var.grafana_cloud_instance_id
  }
}

resource "kubernetes_secret" "honeycomb" {
  metadata {
    name      = "honeycomb"
    namespace = local.namespace
  }

  data = {
    api-key = honeycombio_api_key.prod_ingest.key
  }
}
