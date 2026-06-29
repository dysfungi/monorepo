###############################################################################
# Honeycomb alerting — redundant 2-trigger subset
#
# Grafana Cloud is the PRIMARY alert plane (see grafana_alerts.tf). This file
# adds a small, redundant Honeycomb-native subset that fits HC Free's HARD cap
# of 2 triggers per team — so we spend exactly that budget, no more:
#   1. GatewayServiceSLI  — gateway success-ratio SLO breach (real alert).
#   2. HoneycombUpDeadman — inverted deadman proving the HC pipeline is alive.
#
# Field/dataset names below were VERIFIED against the live `fungi`/prod team via
# the Honeycomb API before authoring (not derived blind):
#   - gateway dataset slug : ngf-gateway-prod-web
#   - status column        : http.status_code  (integer)
#   - latency column       : duration_ms       (float, ms)
#   - deadman dataset slug : automate  (steady ~8 events/min, flat & never 0
#                            over a 15m window; traffic-independent — the most
#                            reliable always-on COUNT source. `metrics` was
#                            rejected: bare COUNT is invalid on metrics datasets;
#                            k8s-logs / calico-node were stale at authoring.)
#
# DEADMAN INVERSION (mirrors grafana_cloud_up in healthchecks_io.tf):
# Honeycomb cannot alert on the ABSENCE of data directly. Instead, the deadman
# trigger fires on EVERY interval that data IS present (alert_type=on_true,
# COUNT > 0) and notifies a webhook recipient whose URL is a healthchecks.io
# ping_url. Each firing pings healthchecks.io, keeping that check green. If the
# HC ingest/trigger pipeline dies, the pings stop and healthchecks.io alerts on
# the missing heartbeat (timeout 30m) via email.
###############################################################################

locals {
  honeycomb_gateway_dataset = "ngf-gateway-prod-web"
  honeycomb_deadman_dataset = "automate"
}

# Email recipient for the real SLI trigger. No honeycombio_email_recipient
# exists elsewhere in the stack, so it is created here.
resource "honeycombio_email_recipient" "alerts" {
  address = "alerts@frank.sh"
}

# healthchecks.io deadman for the Honeycomb pipeline. Mirrors grafana_cloud_up:
# timeout 30m (HC trigger pings every 15m), 10m grace, email channel.
resource "healthchecksio_check" "honeycomb_up" {
  name = "honeycomb-up"
  desc = "Honeycomb alerting deadman — pinged every interval by the HoneycombUpDeadman trigger via its webhook recipient. Silence => HC ingest/trigger pipeline is down."

  timeout  = 1800 # seconds (30m)
  grace    = 600  # seconds (10m)
  channels = [data.healthchecksio_channel.email.id]
}

# Webhook recipient whose URL is the healthchecks.io ping endpoint. The deadman
# trigger notifies this recipient on every firing, producing the heartbeat.
resource "honeycombio_webhook_recipient" "honeycomb_up_deadman" {
  name = "honeycomb-up-deadman"
  url  = healthchecksio_check.honeycomb_up.ping_url
}

# Derived column on the gateway dataset: 1 for a "good" request (non-5xx AND
# under 500ms), else 0. AVG of this column over a window == the success ratio.
resource "honeycombio_derived_column" "gateway_sli" {
  alias       = "sli.gateway_success"
  dataset     = local.honeycomb_gateway_dataset
  description = "SLI: 1 when a gateway request is good (http.status_code < 500 AND duration_ms < 500), else 0. AVG over a window = success ratio."
  expression  = "IF(AND(LT($http.status_code, 500), LT($duration_ms, 500)), 1, 0)"
}

# Query: AVG of the SLI derived column over a 15m window (success ratio).
data "honeycombio_query_specification" "gateway_sli" {
  calculation {
    op     = "AVG"
    column = honeycombio_derived_column.gateway_sli.alias
  }

  time_range = 900 # 15m
}

# Real alert: gateway success ratio drops below 99% over 15m -> email.
resource "honeycombio_trigger" "gateway_sli" {
  name        = "GatewayServiceSLI"
  description = "Gateway success ratio (non-5xx AND <500ms) over 15m fell below 99%. Redundant with the Grafana Cloud gateway RED rules; HC-native backstop."
  dataset     = local.honeycomb_gateway_dataset

  query_json = data.honeycombio_query_specification.gateway_sli.json

  threshold {
    op    = "<"
    value = 0.99
  }

  frequency = 900 # evaluate every 15m

  recipient {
    id = honeycombio_email_recipient.alerts.id
  }

  # Trigger creation references the derived column by alias at the API; ensure
  # the column exists first.
  depends_on = [honeycombio_derived_column.gateway_sli]
}

# Query: COUNT over a 15m window on the steady always-on dataset.
data "honeycombio_query_specification" "honeycomb_up" {
  calculation {
    op = "COUNT"
  }

  time_range = 900 # 15m
}

# Deadman: fires on EVERY interval that data is present (on_true, COUNT > 0),
# pinging the healthchecks.io webhook to keep the check green. See header for
# the full inversion rationale.
resource "honeycombio_trigger" "honeycomb_up_deadman" {
  name        = "HoneycombUpDeadman"
  description = "Heartbeat: fires every 15m while the `automate` dataset has data (COUNT > 0), pinging the honeycomb-up healthcheck. If HC ingest/triggers die, pings stop and healthchecks.io alerts on the absence."
  dataset     = local.honeycomb_deadman_dataset

  query_json = data.honeycombio_query_specification.honeycomb_up.json

  # on_true => notify on every evaluation the condition holds, not just on
  # state transitions. This is what produces the continuous heartbeat.
  alert_type = "on_true"

  threshold {
    op    = ">"
    value = 0
  }

  frequency = 900 # ping every 15m

  recipient {
    id = honeycombio_webhook_recipient.honeycomb_up_deadman.id
  }
}
