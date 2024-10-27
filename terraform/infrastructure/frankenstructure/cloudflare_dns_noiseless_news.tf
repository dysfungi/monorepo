# https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone
resource "cloudflare_zone" "news_noiseless" {
  account_id = data.cloudflare_accounts.dmf.id
  # account_id = resource.cloudflare_account.frankenstructure.id
  zone = "noiseless.news"
}
