resource "vultr_vpc2" "frankenetwork" {
  description = "frankenetwork"
  region      = "lax"
}

resource "vultr_vpc" "k8s" {
  # id = "0dcffa14-ac8e-49cb-8710-3dcc46a97f1f"
  region = "lax"
}
