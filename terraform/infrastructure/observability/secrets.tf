resource "kubernetes_secret" "honeycomb" {
  metadata {
    name      = "honeycomb"
    namespace = local.namespace
  }

  data = {
    api-key = honeycombio_api_key.prod_ingest.key
  }
}
