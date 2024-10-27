# resource "cloudflare_account" "frankenstructure" {
#   name = "frankenstructure"
# }

# https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs
data "cloudflare_accounts" "dmf" {
  name = "dmf"
}
