# Honeycomb alert coverage: condition triggers + per-collector deadman heartbeats.
#
# Triggers are constrained by Honeycomb: exactly ONE calculation, NO formulas, NO
# HEATMAP. Breakdowns ARE allowed (the trigger fires if ANY group crosses the
# threshold). Each query is built via a honeycombio_query_specification data
# source feeding query_json.
#
# Window encoding (Honeycomb rule: query time_range must be <= 4x trigger
# frequency): condition triggers use frequency 900 (15m) except SSL (3600/1h);
# deadman heartbeats use frequency 900 / time_range 900.
#
# DATASET NOTE: synthetics (httpcheck/tlscheck), infra and dotnet metrics all
# land in the `metrics` dataset in this environment (verified against live prod;
# the collectors' x-honeycomb-dataset headers naming `synthetics`/`k8s-metrics`
# do not reflect where the data actually lands). Bare COUNT is rejected on a
# metrics dataset, so metric triggers use MAX/MIN/P90 instead.
#
# DEADMAN OP DEVIATION: the natural deadman op is COUNT_DATAPOINTS (pure
# presence, value-independent), but it is NOT in honeycombio provider v0.35.0's
# calculation-op enum (would fail `tofu validate`), and COUNT is rejected on
# metrics while COUNT_DISTINCT returns no results there. All three deadman
# signals are NON-NEGATIVE gauges, so MAX(<column>) with threshold op ">=" value
# 0 is an equivalent value-independent presence detector: when the collector is
# alive at least one datapoint exists -> MAX >= 0 is true -> fires (on_true) ->
# pings the healthchecks.io check -> check stays green. When the collector dies
# the column stops -> the query returns zero rows -> nothing satisfies the
# threshold -> no fire -> no ping -> the check goes red after its grace period.
# (A value threshold of ">= 1" would NOT work: live k8s.pod.cpu.usage maxes ~0.06
# and systemruntime_exception_count is 0 when healthy.)

###############################################################################
# Recipients
###############################################################################

resource "honeycombio_email_recipient" "alerts" {
  address = "alerts@frank.sh"
}

# One webhook per collector; each posts to the matching healthchecks.io check's
# ping URL. The webhook (NOT email) is the correct recipient for a deadman: the
# heartbeat trigger pings the check on every successful evaluation.
resource "honeycombio_webhook_recipient" "deadman_cluster" {
  name = "deadman-cluster"
  url  = healthchecksio_check.otel_watchdog_cluster.ping_url
}

resource "honeycombio_webhook_recipient" "deadman_daemon" {
  name = "deadman-daemon"
  url  = healthchecksio_check.otel_watchdog_daemon.ping_url
}

resource "honeycombio_webhook_recipient" "deadman_scrape" {
  name = "deadman-scrape"
  url  = healthchecksio_check.otel_watchdog_scrape.ping_url
}

###############################################################################
# Condition triggers
###############################################################################

# 1. Endpoint down (httpcheck.status=1 on a matching status class; the 2xx-class
#    datapoint is emitted with value 0 on failure). MAX < 1 over 30m per URL =>
#    no successful 2xx probe for that endpoint.
data "honeycombio_query_specification" "endpoint_down" {
  calculation {
    op     = "MAX"
    column = "httpcheck.status"
  }
  filter {
    column = "http.status_class"
    op     = "="
    value  = "2xx"
  }
  breakdowns = ["http.url"]
  time_range = 1800
}

resource "honeycombio_trigger" "endpoint_down" {
  name        = "Endpoint down"
  description = "🔴 No successful 2xx synthetic probe for a monitored URL in the last 30m."
  dataset     = "metrics"
  query_json  = data.honeycombio_query_specification.endpoint_down.json
  alert_type  = "on_change"
  frequency   = 900

  threshold {
    op    = "<"
    value = 1
  }

  recipient {
    id = honeycombio_email_recipient.alerts.id
  }
}

# 2. Endpoint slow (p90 httpcheck.duration > 1000ms per URL).
data "honeycombio_query_specification" "endpoint_slow" {
  calculation {
    op     = "P90"
    column = "httpcheck.duration"
  }
  breakdowns = ["http.url"]
  time_range = 3600
}

resource "honeycombio_trigger" "endpoint_slow" {
  name        = "Endpoint slow (p90)"
  description = "🟡 p90 synthetic probe latency for a monitored URL exceeded 1000ms over the last hour."
  dataset     = "metrics"
  query_json  = data.honeycombio_query_specification.endpoint_slow.json
  alert_type  = "on_change"
  frequency   = 900

  threshold {
    op    = ">"
    value = 1000
  }

  recipient {
    id = honeycombio_email_recipient.alerts.id
  }
}

# 3 / 3b. SSL certificate expiry (tlscheck.time_left is seconds-to-expiry per
#    target). One query feeds both the 7-day (warn) and 2-day (critical) triggers.
data "honeycombio_query_specification" "ssl_expiry" {
  calculation {
    op     = "MIN"
    column = "tlscheck.time_left"
  }
  breakdowns = ["tlscheck.target"]
  time_range = 3600
}

resource "honeycombio_trigger" "ssl_expiring_7d" {
  name        = "SSL expiring (<7d)"
  description = "🟡 A monitored TLS certificate expires in under 7 days."
  dataset     = "metrics"
  query_json  = data.honeycombio_query_specification.ssl_expiry.json
  alert_type  = "on_change"
  frequency   = 3600

  threshold {
    op    = "<"
    value = 604800 # 7 days in seconds
  }

  recipient {
    id = honeycombio_email_recipient.alerts.id
  }
}

resource "honeycombio_trigger" "ssl_expiring_2d" {
  name        = "SSL expiring (<2d)"
  description = "🔴 A monitored TLS certificate expires in under 2 days."
  dataset     = "metrics"
  query_json  = data.honeycombio_query_specification.ssl_expiry.json
  alert_type  = "on_change"
  frequency   = 3600

  threshold {
    op    = "<"
    value = 172800 # 2 days in seconds
  }

  recipient {
    id = honeycombio_email_recipient.alerts.id
  }
}

# 4. Gateway 5xx spike. Honeycomb triggers cannot use ratio formulas, so this is
#    an absolute COUNT of 5xx spans (tunable). DEVIATION: this dataset emits the
#    (semconv-deprecated) `http.status_code` column; `http.response.status_code`
#    does not exist here, so the filter uses `http.status_code`.
data "honeycombio_query_specification" "gateway_5xx" {
  calculation {
    op = "COUNT"
  }
  filter {
    column = "http.status_code"
    op     = ">="
    value  = "500"
  }
  time_range = 1800
}

resource "honeycombio_trigger" "gateway_5xx" {
  name        = "Gateway 5xx spike"
  description = "🔴 More than 5 gateway responses with status >= 500 in the last 30m (absolute count; tunable)."
  dataset     = "ngf-gateway-prod-web"
  query_json  = data.honeycombio_query_specification.gateway_5xx.json
  alert_type  = "on_change"
  frequency   = 900

  threshold {
    op    = ">"
    value = 5
  }

  recipient {
    id = honeycombio_email_recipient.alerts.id
  }
}

# 5. Gateway latency (p90 duration_ms). 500ms is generous headroom over the live
#    P99 (~11ms) for a homelab.
data "honeycombio_query_specification" "gateway_latency" {
  calculation {
    op     = "P90"
    column = "duration_ms"
  }
  time_range = 3600
}

resource "honeycombio_trigger" "gateway_latency" {
  name        = "Gateway latency (p90)"
  description = "🟡 Gateway p90 request latency exceeded 500ms over the last hour."
  dataset     = "ngf-gateway-prod-web"
  query_json  = data.honeycombio_query_specification.gateway_latency.json
  alert_type  = "on_change"
  frequency   = 900

  threshold {
    op    = ">"
    value = 500
  }

  recipient {
    id = honeycombio_email_recipient.alerts.id
  }
}

# 6. Pod crashloop (k8s-events is an events dataset, so COUNT is allowed).
data "honeycombio_query_specification" "pod_crashloop" {
  calculation {
    op = "COUNT"
  }
  filter {
    column = "reason"
    op     = "="
    value  = "CrashLoopBackOff"
  }
  breakdowns = ["regarding.name"]
  time_range = 1800
}

resource "honeycombio_trigger" "pod_crashloop" {
  name        = "Pod crashloop"
  description = "🟡 A Kubernetes object reported a CrashLoopBackOff event in the last 30m."
  dataset     = "k8s-events"
  query_json  = data.honeycombio_query_specification.pod_crashloop.json
  alert_type  = "on_change"
  frequency   = 900

  threshold {
    op    = ">"
    value = 0
  }

  recipient {
    id = honeycombio_email_recipient.alerts.id
  }
}

###############################################################################
# Per-collector deadman heartbeats (on_true -> webhook -> healthchecks.io)
###############################################################################

# Cluster collector: signal column httpcheck.status.
data "honeycombio_query_specification" "deadman_cluster" {
  calculation {
    op     = "MAX"
    column = "httpcheck.status"
  }
  filter {
    column = "httpcheck.status"
    op     = "exists"
  }
  time_range = 900
}

resource "honeycombio_trigger" "deadman_cluster" {
  name        = "Deadman: cluster collector"
  description = "💓 Heartbeat — fires while the cluster collector emits httpcheck.status; pings otel-watchdog-cluster."
  dataset     = "metrics"
  query_json  = data.honeycombio_query_specification.deadman_cluster.json
  alert_type  = "on_true"
  frequency   = 900

  threshold {
    op    = ">="
    value = 0
  }

  recipient {
    id = honeycombio_webhook_recipient.deadman_cluster.id
  }
}

# Daemon collector: signal column k8s.pod.cpu.usage.
data "honeycombio_query_specification" "deadman_daemon" {
  calculation {
    op     = "MAX"
    column = "k8s.pod.cpu.usage"
  }
  filter {
    column = "k8s.pod.cpu.usage"
    op     = "exists"
  }
  time_range = 900
}

resource "honeycombio_trigger" "deadman_daemon" {
  name        = "Deadman: daemon collector"
  description = "💓 Heartbeat — fires while the daemon collector emits k8s.pod.cpu.usage; pings otel-watchdog-daemon."
  dataset     = "metrics"
  query_json  = data.honeycombio_query_specification.deadman_daemon.json
  alert_type  = "on_true"
  frequency   = 900

  threshold {
    op    = ">="
    value = 0
  }

  recipient {
    id = honeycombio_webhook_recipient.deadman_daemon.id
  }
}

# Scrape collector: signal column systemruntime_exception_count.
data "honeycombio_query_specification" "deadman_scrape" {
  calculation {
    op     = "MAX"
    column = "systemruntime_exception_count"
  }
  filter {
    column = "systemruntime_exception_count"
    op     = "exists"
  }
  time_range = 900
}

resource "honeycombio_trigger" "deadman_scrape" {
  name        = "Deadman: scrape collector"
  description = "💓 Heartbeat — fires while the scrape collector emits systemruntime_exception_count; pings otel-watchdog-scrape."
  dataset     = "metrics"
  query_json  = data.honeycombio_query_specification.deadman_scrape.json
  alert_type  = "on_true"
  frequency   = 900

  threshold {
    op    = ">="
    value = 0
  }

  recipient {
    id = honeycombio_webhook_recipient.deadman_scrape.id
  }
}
