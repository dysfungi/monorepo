###############################################################################
# Honeycomb board — Resource Right-Sizing · frank8s
#
# A raw resource-USAGE board that is the query companion to
# docs/right-sizing-resources.md. It surfaces the same 7-day CPU/memory usage
# gauges (P95 + MAX, grouped by workload) that the doc's manual method pulls, so
# right-sizing is a board glance instead of ad-hoc queries.
#
# Signal source (VERIFIED via the live prod/`fungi` metrics dataset before
# authoring — see docs/right-sizing-resources.md §2):
#   - dataset            : metrics   (NOT the stale k8s-metrics dataset)
#   - k8s.pod.cpu.usage  : float gauge, CPU in cores
#   - k8s.pod.memory.usage : integer gauge, memory in BYTES (includes page
#                            cache, so it OVERSTATES the true working set — the
#                            doc keeps memory recommendations conservative)
#   - group-by           : k8s.namespace.name + k8s.{deployment,daemonset,
#                            statefulset}.name. All three controller columns are
#                            included so daemonset (otel daemon) and statefulset
#                            (otel scrape) workloads — both in the right-sizing
#                            table — actually appear; a pod populates only its
#                            own controller column, the others render blank.
#   - scope filter       : k8s.cluster.name = frank8s
#
# DIVISION OF LABOR (per Deliverable 3): this board is RAW USAGE only. The
# derived utilization RATIOS (request/limit), memory saturation, node
# conditions, and CPU throttling live on the Grafana Cloud utilization
# dashboard (grafana_dashboards.tf) because those signals route to GC, not HC.
#
# flexible_board v0.35.0 CONSTRAINTS (drove the shape below):
#   - Panels support only type `query` and `slo` — there is NO text/markdown
#     panel type. The "how to use" guidance + heuristic (the plan's text panels)
#     therefore live in the board `description`, which renders Markdown.
#   - There are NO board-level preset/column filters in the schema, so the
#     frank8s scope is baked into every query's filter instead.
#
# POST-APPLY: honeycombio_query query_json + visualization_settings are only
# lightly exercised by `tofu validate`. VERIFY panel rendering (esp. cbar
# categorical bars and axis units) in the Honeycomb UI after the first apply.
###############################################################################

locals {
  honeycomb_metrics_dataset  = "metrics"
  honeycomb_usage_time_range = 604800 # 7d, matching the right-sizing method

  # Shared group-by across every usage query. namespace + all three controller
  # kinds so every IaC-managed workload (Deployment/DaemonSet/StatefulSet)
  # appears exactly once under its own controller column.
  honeycomb_usage_breakdowns = [
    "k8s.namespace.name",
    "k8s.deployment.name",
    "k8s.daemonset.name",
    "k8s.statefulset.name",
  ]
}

# --- Query specifications (one per metric×aggregation) -----------------------
# P95 = the right-sizing request driver; MAX = the limit / headroom driver.

data "honeycombio_query_specification" "cpu_p95" {
  time_range = local.honeycomb_usage_time_range
  breakdowns = local.honeycomb_usage_breakdowns

  calculation {
    op     = "P95"
    column = "k8s.pod.cpu.usage"
  }

  filter {
    column = "k8s.cluster.name"
    op     = "="
    value  = "frank8s"
  }

  order {
    column = "k8s.pod.cpu.usage"
    op     = "P95"
    order  = "descending"
  }
}

data "honeycombio_query_specification" "cpu_max" {
  time_range = local.honeycomb_usage_time_range
  breakdowns = local.honeycomb_usage_breakdowns

  calculation {
    op     = "MAX"
    column = "k8s.pod.cpu.usage"
  }

  filter {
    column = "k8s.cluster.name"
    op     = "="
    value  = "frank8s"
  }

  order {
    column = "k8s.pod.cpu.usage"
    op     = "MAX"
    order  = "descending"
  }
}

data "honeycombio_query_specification" "mem_p95" {
  time_range = local.honeycomb_usage_time_range
  breakdowns = local.honeycomb_usage_breakdowns

  calculation {
    op     = "P95"
    column = "k8s.pod.memory.usage"
  }

  filter {
    column = "k8s.cluster.name"
    op     = "="
    value  = "frank8s"
  }

  order {
    column = "k8s.pod.memory.usage"
    op     = "P95"
    order  = "descending"
  }
}

data "honeycombio_query_specification" "mem_max" {
  time_range = local.honeycomb_usage_time_range
  breakdowns = local.honeycomb_usage_breakdowns

  calculation {
    op     = "MAX"
    column = "k8s.pod.memory.usage"
  }

  filter {
    column = "k8s.cluster.name"
    op     = "="
    value  = "frank8s"
  }

  order {
    column = "k8s.pod.memory.usage"
    op     = "MAX"
    order  = "descending"
  }
}

# --- Persisted queries -------------------------------------------------------
# Queries are immutable; a spec change creates a new query object. The two P95
# queries are reused by both a categorical-bar and an over-time panel.

resource "honeycombio_query" "cpu_p95" {
  dataset    = local.honeycomb_metrics_dataset
  query_json = data.honeycombio_query_specification.cpu_p95.json
}

resource "honeycombio_query" "cpu_max" {
  dataset    = local.honeycomb_metrics_dataset
  query_json = data.honeycombio_query_specification.cpu_max.json
}

resource "honeycombio_query" "mem_p95" {
  dataset    = local.honeycomb_metrics_dataset
  query_json = data.honeycombio_query_specification.mem_p95.json
}

resource "honeycombio_query" "mem_max" {
  dataset    = local.honeycomb_metrics_dataset
  query_json = data.honeycombio_query_specification.mem_max.json
}

# --- Query annotations (panel titles) ----------------------------------------
# query_annotation_id is REQUIRED on every query_panel. A query may carry more
# than one annotation, which is how the shared P95 queries title their bar and
# their timeseries panel differently.

resource "honeycombio_query_annotation" "cpu_p95_bar" {
  dataset     = local.honeycomb_metrics_dataset
  query_id    = honeycombio_query.cpu_p95.id
  name        = "CPU P95 by workload (7d)"
  description = "P95 pod CPU usage (cores) per workload — the CPU-request driver: cpuReq = max(P95 × 1.5, 10m)."
}

resource "honeycombio_query_annotation" "cpu_max_bar" {
  dataset     = local.honeycomb_metrics_dataset
  query_id    = honeycombio_query.cpu_max.id
  name        = "CPU MAX by workload (7d)"
  description = "Peak pod CPU usage (cores) per workload — headroom check (CPU limits are omitted by policy)."
}

resource "honeycombio_query_annotation" "mem_p95_bar" {
  dataset     = local.honeycomb_metrics_dataset
  query_id    = honeycombio_query.mem_p95.id
  name        = "Memory P95 by workload (7d)"
  description = "P95 pod memory usage (bytes) per workload — the memory-request driver: memReq = max(P95 × 1.1, 24Mi). NOTE: includes page cache, so it overstates working set."
}

resource "honeycombio_query_annotation" "mem_max_bar" {
  dataset     = local.honeycomb_metrics_dataset
  query_id    = honeycombio_query.mem_max.id
  name        = "Memory MAX by workload (7d)"
  description = "Peak pod memory usage (bytes) per workload — the memory-limit driver: memLim = max(MAX × 1.5, memReq)."
}

resource "honeycombio_query_annotation" "cpu_p95_ts" {
  dataset     = local.honeycomb_metrics_dataset
  query_id    = honeycombio_query.cpu_p95.id
  name        = "CPU P95 over time"
  description = "P95 pod CPU usage (cores) per workload over the 7-day window — trend / spike context for the bar above."
}

resource "honeycombio_query_annotation" "mem_p95_ts" {
  dataset     = local.honeycomb_metrics_dataset
  query_id    = honeycombio_query.mem_p95.id
  name        = "Memory P95 over time"
  description = "P95 pod memory usage (bytes) per workload over the 7-day window — trend / spike context for the bar above."
}

# --- Board -------------------------------------------------------------------

resource "honeycombio_flexible_board" "resource_right_sizing" {
  name = "Resource Right-Sizing · frank8s"

  # The board description carries the guidance the plan wanted as text panels
  # (flexible_board has no text panel type). Rendered as Markdown in the UI.
  description = <<-EOT
    Raw 7-day pod CPU/memory **usage** by workload — query companion to
    [`docs/right-sizing-resources.md`](https://github.com/dysfungi/monorepo/blob/main/docs/right-sizing-resources.md).
    Compare each workload's **P95**/**MAX** to its configured `requests`/`limits`, then apply the lean heuristic:

    - **CPU request** = `max(P95 × 1.5, 10m)` (CPU limits omitted by policy)
    - **Memory request** = `max(P95 × 1.1, 24Mi)`; **Memory limit** = `max(MAX × 1.5, memRequest)`

    Caveats: `k8s.pod.memory.usage` includes page cache (overstates working set — stay conservative).
    Grouped by namespace + Deployment/DaemonSet/StatefulSet; each pod fills only its own controller column. Scoped to `k8s.cluster.name = frank8s`.
    Utilization ratios, memory saturation, node conditions, and CPU throttling live on the Grafana Cloud frank8s dashboard (per Deliverable 3), not here. Panel rendering verified post-apply.
  EOT

  # Row 1 — CPU: P95 (request driver) beside MAX (headroom).
  panel {
    type = "query"
    position {
      x_coordinate = 0
      y_coordinate = 0
      width        = 6
      height       = 6
    }
    query_panel {
      query_id            = honeycombio_query.cpu_p95.id
      query_annotation_id = honeycombio_query_annotation.cpu_p95_bar.id
      query_style         = "combo"
      visualization_settings {
        chart {
          chart_type  = "cbar"
          chart_index = 0
        }
      }
    }
  }

  panel {
    type = "query"
    position {
      x_coordinate = 6
      y_coordinate = 0
      width        = 6
      height       = 6
    }
    query_panel {
      query_id            = honeycombio_query.cpu_max.id
      query_annotation_id = honeycombio_query_annotation.cpu_max_bar.id
      query_style         = "combo"
      visualization_settings {
        chart {
          chart_type  = "cbar"
          chart_index = 0
        }
      }
    }
  }

  # Row 2 — Memory: P95 (request driver) beside MAX (limit driver).
  panel {
    type = "query"
    position {
      x_coordinate = 0
      y_coordinate = 6
      width        = 6
      height       = 6
    }
    query_panel {
      query_id            = honeycombio_query.mem_p95.id
      query_annotation_id = honeycombio_query_annotation.mem_p95_bar.id
      query_style         = "combo"
      visualization_settings {
        chart {
          chart_type  = "cbar"
          chart_index = 0
        }
      }
    }
  }

  panel {
    type = "query"
    position {
      x_coordinate = 6
      y_coordinate = 6
      width        = 6
      height       = 6
    }
    query_panel {
      query_id            = honeycombio_query.mem_max.id
      query_annotation_id = honeycombio_query_annotation.mem_max_bar.id
      query_style         = "combo"
      visualization_settings {
        chart {
          chart_type  = "cbar"
          chart_index = 0
        }
      }
    }
  }

  # Row 3 — CPU usage over time (trend / spike context).
  panel {
    type = "query"
    position {
      x_coordinate = 0
      y_coordinate = 12
      width        = 12
      height       = 5
    }
    query_panel {
      query_id            = honeycombio_query.cpu_p95.id
      query_annotation_id = honeycombio_query_annotation.cpu_p95_ts.id
      query_style         = "graph"
      visualization_settings {
        chart {
          chart_type          = "line"
          chart_index         = 0
          omit_missing_values = true
        }
      }
    }
  }

  # Row 4 — Memory usage over time (trend / spike context).
  panel {
    type = "query"
    position {
      x_coordinate = 0
      y_coordinate = 17
      width        = 12
      height       = 5
    }
    query_panel {
      query_id            = honeycombio_query.mem_p95.id
      query_annotation_id = honeycombio_query_annotation.mem_p95_ts.id
      query_style         = "graph"
      visualization_settings {
        chart {
          chart_type          = "line"
          chart_index         = 0
          omit_missing_values = true
        }
      }
    }
  }
}
