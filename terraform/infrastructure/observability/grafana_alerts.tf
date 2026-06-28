###############################################################################
# Grafana Cloud alerting — Phase 2
#
# Provisions Grafana-managed alert rules, contact points, a notification policy,
# and a deadman healthcheck against the `fungi` Grafana Cloud stack. Signals come
# from Phase 1a/1b routing:
#   - synthetics (httpcheck / tlscheck)         -> Prometheus metrics in GC
#   - gateway RED (spanmetrics calls/duration)  -> Prometheus metrics in GC
#
# DERIVED NAMES — VERIFY AT APPLY against the live GC `fungi` stack. Derived from
# the OTLP->Prometheus naming convention (dots/dashes -> '_', unit/_total
# suffixes) + GC default datasource naming; NOT yet confirmed against live data:
#   datasource name  : grafanacloud-fungi-prom
#   synthetic up     : httpcheck_status{http_status_class,http_url}   (1=success)
#   synthetic latency: httpcheck_duration_milliseconds{http_url}      (ms)
#   ssl remaining    : tlscheck_time_left_seconds{tlscheck_target}    (seconds)
#   gateway calls    : calls_total{service_name,http_status_code,...}
#   gateway duration : duration_milliseconds_bucket{le,service_name,...}
#
# no_data_state / exec_err_state are "OK" on threshold rules so an incorrect
# derived metric name (-> empty/erroring query) does NOT spuriously fire during
# this unverified rollout. Revisit once metric names are confirmed at apply.
#
# Collector-liveness + crashloop rules are DEFERRED to Phase 1c (need collector
# self-telemetry routing) and are intentionally NOT defined here.
###############################################################################

data "grafana_data_source" "prom" {
  # GC default Prometheus datasource for stack slug `fungi`. VERIFY at apply.
  name = "grafanacloud-fungi-prom"
}

resource "grafana_folder" "observability" {
  title = "Observability Alerts"
}

resource "grafana_contact_point" "email" {
  name = "email-alerts"

  email {
    addresses = ["alerts@frank.sh"]
  }
}

resource "grafana_contact_point" "deadman_gc" {
  name = "deadman-grafana-cloud"

  webhook {
    # Pinged on every Watchdog re-notify; feeds the healthchecks.io deadman.
    url = healthchecksio_check.grafana_cloud_up.ping_url
  }
}

resource "grafana_notification_policy" "root" {
  # Root tree: email is the catch-all receiver.
  contact_point = grafana_contact_point.email.name
  group_by      = ["alertname"]

  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "4h"

  # Deadman route: the always-firing Watchdog rule (alertname="Watchdog") pings
  # the GC healthcheck every repeat_interval, so a stalled Grafana alerting
  # engine is detected by healthchecks.io flipping to down.
  policy {
    matcher {
      label = "alertname"
      match = "="
      value = "Watchdog"
    }
    contact_point   = grafana_contact_point.deadman_gc.name
    continue        = false
    group_wait      = "30s"
    group_interval  = "5m"
    repeat_interval = "10m"
  }
}

locals {
  # Each rule = an instant PromQL query (ref_id A) feeding a server-side
  # threshold expression (ref_id C); condition = "C". The threshold comparison
  # lives in the expression node, not in PromQL.
  grafana_alert_rules = {
    synthetic_endpoint_down = {
      title     = "SyntheticEndpointDown 🔴"
      expr      = "avg_over_time(httpcheck_status{http_status_class=\"2xx\"}[10m])"
      evaluator = "lt"
      threshold = 0.99
      for       = "5m"
      from      = 600
      severity  = "critical"
      summary   = "Synthetic endpoint {{ $labels.http_url }} 2xx success ratio < 99% over 10m."
    }
    synthetic_latency_high = {
      title     = "SyntheticLatencyHigh 🟡"
      expr      = "quantile_over_time(0.9, httpcheck_duration_milliseconds[1h])"
      evaluator = "gt"
      threshold = 1000
      for       = "10m"
      from      = 3600
      severity  = "warning"
      summary   = "Synthetic endpoint {{ $labels.http_url }} p90 latency > 1000ms over 1h."
    }
    ssl_expiring_soon = {
      title     = "SSLExpiringSoon 🟡"
      expr      = "min by (tlscheck_target) (tlscheck_time_left_seconds)"
      evaluator = "lt"
      threshold = 604800
      for       = "1h"
      from      = 600
      severity  = "warning"
      summary   = "TLS certificate for {{ $labels.tlscheck_target }} expires in < 7d."
    }
    ssl_expiring_critical = {
      title     = "SSLExpiringCritical 🔴"
      expr      = "min by (tlscheck_target) (tlscheck_time_left_seconds)"
      evaluator = "lt"
      threshold = 172800
      for       = "1h"
      from      = 600
      severity  = "critical"
      summary   = "TLS certificate for {{ $labels.tlscheck_target }} expires in < 2d."
    }
    gateway_error_rate = {
      title     = "GatewayErrorRate 🔴"
      expr      = "sum(rate(calls_total{service_name=\"nginx-gateway-fabric\",http_status_code=~\"5..\"}[5m])) / sum(rate(calls_total{service_name=\"nginx-gateway-fabric\"}[5m]))"
      evaluator = "gt"
      threshold = 0.05
      for       = "5m"
      from      = 600
      severity  = "critical"
      summary   = "nginx-gateway-fabric 5xx error rate > 5% over 5m."
    }
    gateway_latency_high = {
      title     = "GatewayLatencyHigh 🟡"
      expr      = "histogram_quantile(0.9, sum by (le) (rate(duration_milliseconds_bucket{service_name=\"nginx-gateway-fabric\"}[5m])))"
      evaluator = "gt"
      threshold = 500
      for       = "10m"
      from      = 600
      severity  = "warning"
      summary   = "nginx-gateway-fabric p90 request duration > 500ms over 5m."
    }
    watchdog = {
      # Always-firing deadman. alertname="Watchdog" routes to deadman_gc.
      title     = "Watchdog"
      expr      = "vector(1)"
      evaluator = "gt"
      threshold = 0
      for       = "0"
      from      = 600
      severity  = "none"
      summary   = "Deadman heartbeat — always firing; pings the GC healthcheck."
    }
  }
}

resource "grafana_rule_group" "observability" {
  name             = "observability"
  folder_uid       = grafana_folder.observability.uid
  interval_seconds = 60

  dynamic "rule" {
    for_each = local.grafana_alert_rules
    content {
      name      = rule.value.title
      condition = "C"
      for       = rule.value.for

      # Quiet during the unverified rollout: empty/erroring derived queries must
      # not page. Re-evaluate once metric names are confirmed at apply.
      no_data_state  = "OK"
      exec_err_state = "OK"

      labels = {
        severity = rule.value.severity
      }
      annotations = {
        summary = rule.value.summary
      }

      data {
        ref_id = "A"
        relative_time_range {
          from = rule.value.from
          to   = 0
        }
        datasource_uid = data.grafana_data_source.prom.uid
        model = jsonencode({
          refId         = "A"
          datasource    = { type = "prometheus", uid = data.grafana_data_source.prom.uid }
          expr          = rule.value.expr
          instant       = true
          range         = false
          intervalMs    = 1000
          maxDataPoints = 43200
          hide          = false
        })
      }

      data {
        ref_id = "C"
        relative_time_range {
          from = 0
          to   = 0
        }
        datasource_uid = "-100"
        model = jsonencode({
          refId      = "C"
          type       = "threshold"
          datasource = { type = "__expr__", uid = "__expr__" }
          expression = "A"
          conditions = [{
            type      = "query"
            evaluator = { type = rule.value.evaluator, params = [rule.value.threshold] }
            operator  = { type = "and" }
            query     = { params = ["C"] }
            reducer   = { type = "last", params = [] }
          }]
          hide = false
        })
      }
    }
  }
}
