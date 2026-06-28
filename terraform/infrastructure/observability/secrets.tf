# The grafana-cloud Secret is no longer provisioned here: it is now an
# ExternalSecret reconciled by the External Secrets Operator from 1Password
# (see external_secret_grafana_cloud.tf). The honeycomb Secret stays in
# Terraform because its api-key is provider-generated (honeycombio_api_key),
# not a pre-existing 1Password item.
resource "kubernetes_secret" "honeycomb" {
  metadata {
    name      = "honeycomb"
    namespace = local.namespace
  }

  data = {
    api-key = honeycombio_api_key.prod_ingest.key
  }
}
