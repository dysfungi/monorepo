# https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone
resource "cloudflare_zone" "sh_frank" {
  # account_id = resource.cloudflare_account.frankenstructure.id
  account_id = data.cloudflare_accounts.dmf.id
  zone       = "frank.sh"
}

resource "cloudflare_record" "sh_frank_remy" {
  zone_id = resource.cloudflare_zone.sh_frank.id
  name    = "remy"
  type    = "CNAME"
  content = "remyfrank01.github.io"
  proxied = true
  ttl     = local.cloudflare_auto_ttl
}

resource "cloudflare_record" "sh_frank_remington" {
  zone_id = resource.cloudflare_zone.sh_frank.id
  name    = "remington"
  type    = "CNAME"
  content = "remy.frank.sh"
  proxied = true
  ttl     = local.cloudflare_auto_ttl
}
