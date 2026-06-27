# Dedicated scrape collector: a StatefulSet whose targetAllocator discovers the
# existing Prometheus Operator ServiceMonitor/PodMonitor CRs (prometheusCR mode)
# and hands their targets to the embedded prometheus receiver via http_sd. The
# operator rewires `receivers.prometheus` to the target allocator automatically
# when `targetAllocator.enabled = true` and a `prometheus` receiver is present.
#
# Exporter/extension inheritance: this collector intentionally does NOT redeclare
# `otlp/honeycomb-k8s-metrics` (exporter), `filter/metrics-dotnet`/`memory_limiter`/
# `batch` (processors), or `basicauth/grafana-cloud` (extension). The
# opentelemetry-kube-stack chart layers every collector on top of `defaultCRConfig`
# (= local.base_collector) -- the same inheritance the cluster_collector and
# daemon_collector pipelines already rely on (they reference these names without
# defining them). The merge is therefore confirmed, not assumed; see
# base_collector.tf for the definitions.
#
# targetAllocator schema is the OpenTelemetryCollector spec.targetAllocator field
# (sibling to mode/replicas/config), per opentelemetry-kube-stack 0.6.1 values.yaml.
# Discovery is scoped to the single automate-api PodMonitor via an explicit label
# selector (see prometheusCR below); the CRD's prometheusCR does not support a
# namespace selector, so the PodMonitor carries an `otel-scrape = automate` label.
locals {
  scrape_collector = {
    enabled  = true
    mode     = "statefulset"
    replicas = 1

    # The target allocator + prometheus receiver are memory-hungry relative to
    # the chart/operator defaults; bump the floor and ceiling so the StatefulSet
    # stops OOM-restarting. (No explicit resources block existed previously --
    # these values replace the inherited defaults.)
    resources = {
      requests = {
        memory = "128Mi"
      }
      limits = {
        memory = "512Mi"
      }
    }

    # Collector pods scrape the discovered targets; this SA carries the
    # nodes/services/endpoints/pods read permissions (see scrape_collector_rbac.tf).
    serviceAccount = kubernetes_service_account.scrape_collector.metadata[0].name

    # Disable the chart's default prometheus scrape_configs injection; targets come
    # exclusively from the target allocator's prometheusCR discovery.
    scrape_configs_file = ""

    targetAllocator = {
      enabled            = true
      allocationStrategy = "consistent-hashing"
      filterStrategy     = "relabel-config"
      # Read access to the monitoring.coreos.com CRs + namespaces (see RBAC file).
      serviceAccount = kubernetes_service_account.scrape_target_allocator.metadata[0].name
      prometheusCR = {
        enabled = true
        # Scope discovery to ONLY the automate-api PodMonitor. The CRD's
        # prometheusCR does NOT support podMonitorNamespaceSelector (only
        # podMonitorSelector + serviceMonitorSelector, both label selectors); a
        # namespace selector here is silently ignored, so the allocator would
        # otherwise discover every monitor cluster-wide and OOM. We therefore
        # scope by an explicit label set on the PodMonitor itself (otel-scrape =
        # automate; see fsharp/api/automate/terraform/monitors.tf). ServiceMonitors
        # are matched by an impossible label so none are scraped.
        podMonitorSelector = {
          matchLabels = {
            "otel-scrape" = "automate"
          }
        }
        serviceMonitorSelector = {
          matchLabels = {
            "app.kubernetes.io/component" = "__match-nothing__"
          }
        }
        scrapeInterval = "30s"
      }
    }

    config = {
      receivers = {
        prometheus = {
          # The target allocator injects targets via http_sd; the static
          # scrape_configs list stays empty.
          config = {
            scrape_configs = []
          }
        }
      }
      processors = {
        # Inherited from base_collector (defaultCRConfig); listed here only so the
        # pipeline references resolve. memory_limiter, batch, and
        # filter/metrics-dotnet are defined there.
      }
      exporters = {
        # Inherited from base_collector: "debug" and "otlp/honeycomb-k8s-metrics".
      }
      service = {
        pipelines = {
          metrics = {
            receivers = [
              "prometheus",
            ]
            processors = [
              "memory_limiter",
              # Allowlist down to just the .NET exception counter; drop the rest.
              "filter/metrics-dotnet",
              "batch",
            ]
            exporters = [
              "debug",
              # Grafana Cloud unrouted; route the curated dotnet metric to
              # Honeycomb (k8s-metrics dataset).
              "otlp/honeycomb-k8s-metrics",
            ]
          }
        }
      }
    }
  }
}
