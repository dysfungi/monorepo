data "healthchecksio_channel" "email" {
  kind = "email"
}

# One watchdog check per OpenTelemetry collector. Each is a simple (period-based)
# check: the matching Honeycomb deadman heartbeat trigger pings ping_url every
# ~15m while the collector emits data. timeout 900s + grace 600s => the check
# flips to "down" (and emails via the channel) if no ping arrives for 25m.
resource "healthchecksio_check" "otel_watchdog_cluster" {
  name    = "otel-watchdog-cluster"
  desc    = "Deadman for the OpenTelemetry cluster collector (httpcheck.status heartbeat)"
  timeout = 900 # seconds
  grace   = 600 # seconds
  channels = [
    data.healthchecksio_channel.email.id,
  ]
}

resource "healthchecksio_check" "otel_watchdog_daemon" {
  name    = "otel-watchdog-daemon"
  desc    = "Deadman for the OpenTelemetry daemon collector (k8s.pod.cpu.usage heartbeat)"
  timeout = 900 # seconds
  grace   = 600 # seconds
  channels = [
    data.healthchecksio_channel.email.id,
  ]
}

resource "healthchecksio_check" "otel_watchdog_scrape" {
  name    = "otel-watchdog-scrape"
  desc    = "Deadman for the OpenTelemetry scrape collector (systemruntime_exception_count heartbeat)"
  timeout = 900 # seconds
  grace   = 600 # seconds
  channels = [
    data.healthchecksio_channel.email.id,
  ]
}
