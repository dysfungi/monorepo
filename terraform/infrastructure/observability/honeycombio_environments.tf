# https://registry.terraform.io/providers/honeycombio/honeycombio/latest/docs/data-sources/environment
data "honeycombio_environment" "test" {
  detail_filter {
    name  = "name"
    value = "test"
  }
}

# https://registry.terraform.io/providers/honeycombio/honeycombio/latest/docs/resources/environment
resource "honeycombio_environment" "prod" {
  name             = "prod"
  color            = "green"
  description      = "Production"
  delete_protected = true
}
