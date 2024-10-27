# https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone
resource "cloudflare_zone" "training_petiquette" {
  account_id = data.cloudflare_accounts.dmf.id
  # account_id = resource.cloudflare_account.frankenstructure.id
  zone = "petiquette.training"
}
