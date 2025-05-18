# https://registry.terraform.io/providers/honeycombio/honeycombio/latest/docs/resources/api_key
resource "honeycombio_api_key" "prod_ingest" {
  name           = "prod-ingest"
  type           = "ingest"
  environment_id = honeycombio_environment.prod.id

  permissions {
    create_datasets = true
  }
}
