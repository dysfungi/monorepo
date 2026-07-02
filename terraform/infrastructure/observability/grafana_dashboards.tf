###############################################################################
# Grafana Cloud dashboard — frank8s utilization & saturation
#
# The utilization/saturation companion to the Honeycomb raw-usage board
# (honeycomb_boards.tf). Per Deliverable 3, the derived RATIO / saturation /
# node-condition / CPU-throttling signals route to Grafana Cloud (billed per
# active series, not per datapoint), so they are dashboarded HERE while the raw
# usage gauges stay on Honeycomb.
#
# Provider auth is REUSED from grafana_alerts.tf (var.grafana_url +
# var.grafana_auth glsa token against the `fungi` GC stack) — no new secret is
# introduced. The Prometheus datasource is the same data.grafana_data_source.prom.
#
# DERIVED METRIC NAMES — VERIFY AT APPLY (same caveat as grafana_alerts.tf):
# these PromQL names are the OTLP->Prometheus normalization of the OTel metric
# names D3 routes to GC (dots -> '_'; byte-unit gauges gain a `_bytes` suffix;
# monotonic sums keep `_total`). They are NOT yet confirmed against live GC
# series. A wrong name renders an empty panel ("No data") — harmless for a
# dashboard (unlike an alert), but confirm and correct after the first apply.
#   OTel (see daemon_collector.tf / base_collector.tf filter/metrics-utilization):
#     k8s.pod.cpu_request_utilization    -> k8s_pod_cpu_request_utilization
#     k8s.pod.cpu_limit_utilization      -> k8s_pod_cpu_limit_utilization
#     k8s.pod.memory_request_utilization -> k8s_pod_memory_request_utilization
#     k8s.pod.memory_limit_utilization   -> k8s_pod_memory_limit_utilization
#     k8s.pod.memory.working_set         -> k8s_pod_memory_working_set_bytes
#     k8s.node.condition_ready           -> k8s_node_condition_ready
#   cAdvisor scrape (scrape_collector.tf metrics/cadvisor), already Prom-named:
#     container_cpu_cfs_throttled_periods_total, container_cpu_cfs_periods_total
###############################################################################

resource "grafana_folder" "dashboards" {
  title = "Observability Dashboards"
}

locals {
  # Prometheus label names are the OTLP resource-attribute normalization
  # (k8s.namespace.name -> k8s_namespace_name, etc.).
  gc_pod_legend = "{{k8s_namespace_name}}/{{k8s_pod_name}}"

  # Ordered timeseries panels; rendered 2-up. `unit` uses Grafana unit ids
  # (`percentunit` = 0..1 ratio, `bytes` = IEC bytes, `none` = raw ratio).
  gc_utilization_ts_panels = [
    {
      title = "Pod CPU request utilization"
      expr  = "k8s_pod_cpu_request_utilization{k8s_namespace_name=~\"$namespace\"}"
      unit  = "percentunit"
      desc  = "Pod CPU usage / CPU request. > 1 means the pod routinely exceeds its request (request likely too low); persistently << 1 means the request is over-declared (reclaim candidate)."
    },
    {
      title = "Pod CPU limit utilization"
      expr  = "k8s_pod_cpu_limit_utilization{k8s_namespace_name=~\"$namespace\"}"
      unit  = "percentunit"
      desc  = "Pod CPU usage / CPU limit. CPU limits are omitted by policy on frank8s, so this is typically empty — kept for any workload that still carries a CPU limit."
    },
    {
      title = "Pod memory request utilization"
      expr  = "k8s_pod_memory_request_utilization{k8s_namespace_name=~\"$namespace\"}"
      unit  = "percentunit"
      desc  = "Pod memory usage / memory request. Sustained > 1 is an eviction risk under node pressure (raise the request); << 1 is over-declared."
    },
    {
      title = "Pod memory limit utilization"
      expr  = "k8s_pod_memory_limit_utilization{k8s_namespace_name=~\"$namespace\"}"
      unit  = "percentunit"
      desc  = "Pod memory usage / memory limit. Approaching 1 is an imminent OOMKill risk — the primary memory-saturation signal."
    },
    {
      title = "Pod memory working set"
      expr  = "k8s_pod_memory_working_set_bytes{k8s_namespace_name=~\"$namespace\"}"
      unit  = "bytes"
      desc  = "Working-set memory (excludes reclaimable page cache) — the honest memory footprint to size requests/limits against, vs the cache-inflated k8s.pod.memory.usage on the Honeycomb board."
    },
    {
      title = "Pod CPU throttling ratio"
      expr  = "sum by (k8s_namespace_name, k8s_pod_name) (rate(container_cpu_cfs_throttled_periods_total{k8s_namespace_name=~\"$namespace\"}[5m])) / sum by (k8s_namespace_name, k8s_pod_name) (rate(container_cpu_cfs_periods_total{k8s_namespace_name=~\"$namespace\"}[5m]))"
      unit  = "percentunit"
      desc  = "Fraction of CFS periods in which a container was throttled. Non-zero here on a workload WITH a CPU limit is the #1 CPU-saturation signal (tail-latency hit). Expected ~0 fleet-wide since CPU limits are omitted by policy."
    },
  ]
}

# https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/dashboard
resource "grafana_dashboard" "frank8s_utilization" {
  folder = grafana_folder.dashboards.uid

  # overwrite so re-applies replace the managed dashboard in place rather than
  # colliding on the uid.
  overwrite = true

  config_json = jsonencode({
    uid           = "frank8s-utilization"
    title         = "frank8s · Utilization & Saturation"
    tags          = ["frank8s", "utilization", "right-sizing", "managed-by:tofu"]
    timezone      = "utc"
    schemaVersion = 39
    editable      = true
    time          = { from = "now-7d", to = "now" }
    templating = {
      list = [
        {
          name       = "namespace"
          label      = "Namespace"
          type       = "query"
          datasource = { type = "prometheus", uid = data.grafana_data_source.prom.uid }
          query      = { query = "label_values(k8s_pod_memory_working_set_bytes, k8s_namespace_name)", refId = "namespace" }
          refresh    = 2
          includeAll = true
          # all-value is a regex so "All" (paired with =~ in every pod/container
          # expr) matches every namespace; without it $namespace would expand to
          # the literal "$__all" and every wired panel would go "No data".
          allValue = ".*"
          multi    = true
          current  = { text = "All", value = "$__all" }
        },
      ]
    }

    panels = concat(
      # Header / how-to-use + derived-name caveat (flexible text panel).
      [
        {
          type    = "text"
          title   = "About this dashboard"
          gridPos = { h = 3, w = 24, x = 0, y = 0 }
          options = {
            mode    = "markdown"
            content = <<-EOT
              GC utilization & saturation companion to the Honeycomb **Resource Right-Sizing · frank8s** board and [`docs/right-sizing-resources.md`](https://github.com/dysfungi/monorepo/blob/main/docs/right-sizing-resources.md). Ratios are `usage / request` and `usage / limit`: **> 1** request-utilization ⇒ raise the request; **≈ 1** limit-utilization ⇒ OOM/throttle risk; **≪ 1** ⇒ reclaim candidate. Metric names are DERIVED from the OTel→Prom normalization and are verified post-apply.
            EOT
          }
        },
      ],
      # Utilization / saturation timeseries, laid out 2-up (12-col halves).
      [
        for i, p in local.gc_utilization_ts_panels : {
          type        = "timeseries"
          title       = p.title
          description = p.desc
          datasource  = { type = "prometheus", uid = data.grafana_data_source.prom.uid }
          gridPos = {
            h = 8
            w = 12
            x = (i % 2) * 12
            y = 3 + floor(i / 2) * 8
          }
          fieldConfig = {
            defaults  = { unit = p.unit, custom = { drawStyle = "line", fillOpacity = 10, showPoints = "never" } }
            overrides = []
          }
          options = { legend = { displayMode = "table", placement = "bottom", calcs = ["last", "max"] } }
          targets = [
            {
              refId        = "A"
              datasource   = { type = "prometheus", uid = data.grafana_data_source.prom.uid }
              expr         = p.expr
              legendFormat = local.gc_pod_legend
            },
          ]
        }
      ],
      # Node conditions — one series per node per condition; 1 = asserted.
      [
        {
          type        = "timeseries"
          title       = "Node conditions (1 = asserted)"
          description = "k8s_node_condition_ready should be 1 for every node; the *_pressure conditions should be 0. Any memory/disk/pid pressure asserting is a node-saturation event and the failover scenario the right-sizing exercise protects."
          datasource  = { type = "prometheus", uid = data.grafana_data_source.prom.uid }
          gridPos     = { h = 8, w = 24, x = 0, y = 3 + ceil(length(local.gc_utilization_ts_panels) / 2.0) * 8 }
          fieldConfig = {
            defaults  = { unit = "none", custom = { drawStyle = "line", fillOpacity = 10, showPoints = "never" } }
            overrides = []
          }
          options = { legend = { displayMode = "table", placement = "bottom", calcs = ["last"] } }
          targets = [
            { refId = "A", datasource = { type = "prometheus", uid = data.grafana_data_source.prom.uid }, expr = "k8s_node_condition_ready", legendFormat = "{{k8s_node_name}} ready" },
            { refId = "B", datasource = { type = "prometheus", uid = data.grafana_data_source.prom.uid }, expr = "k8s_node_condition_memory_pressure", legendFormat = "{{k8s_node_name}} mem-pressure" },
            { refId = "C", datasource = { type = "prometheus", uid = data.grafana_data_source.prom.uid }, expr = "k8s_node_condition_disk_pressure", legendFormat = "{{k8s_node_name}} disk-pressure" },
            { refId = "D", datasource = { type = "prometheus", uid = data.grafana_data_source.prom.uid }, expr = "k8s_node_condition_pid_pressure", legendFormat = "{{k8s_node_name}} pid-pressure" },
          ]
        },
      ],
    )
  })
}
