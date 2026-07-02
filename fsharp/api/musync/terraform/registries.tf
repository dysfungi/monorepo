# https://registry.terraform.io/providers/vultr/vultr/latest/docs/data-sources/container_registry
data "vultr_container_registry" "frankistry" {
  filter {
    name = "name"
    values = [
      "frankistry",
    ]
  }
}
