# https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone
resource "cloudflare_zone" "com_derekmfrank" {
  account_id = data.cloudflare_accounts.dmf.id
  # account_id = resource.cloudflare_account.frankenstructure.id
  zone = "derekmfrank.com"
}
