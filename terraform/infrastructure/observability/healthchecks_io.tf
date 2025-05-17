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
