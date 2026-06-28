data "healthchecksio_channel" "email" {
  kind = "email"
}

# resource "healthchecksio_check" "watchdog" {
#   name = "frankenstructure-opentelemetry-watchdog"
#   desc = "OpenTelemetry Operator Watchdog for Frankenstructure"
#
#   grace    = 600 # seconds
#   schedule = "* * * * *"
#   timezone = "America/Los_Angeles"
#   channels = [
#     data.healthchecksio_channel.email.id,
#   ]
# }

resource "healthchecksio_check" "grafana_cloud_up" {
  name = "grafana-cloud-up"
  desc = "Grafana Cloud alerting deadman — pinged by the always-firing Watchdog rule via the deadman webhook contact point."

  timeout  = 1800 # seconds (30m); GC Watchdog re-notifies every 10m
  grace    = 600  # seconds
  channels = [data.healthchecksio_channel.email.id]
}
