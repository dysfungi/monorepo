data "healthchecksio_channel" "email" {
  kind = "email"
}

resource "healthchecksio_check" "prom_watchdog" {
  name = "frankenstructure-prom-operator-watchdog"
  desc = "Prometheus Operator Watchdog for Frankenstructure"

  grace    = 600 # seconds
  schedule = "* * * * *"
  timezone = "America/Los_Angeles"
  channels = [
    data.healthchecksio_channel.email.id,
  ]
}
