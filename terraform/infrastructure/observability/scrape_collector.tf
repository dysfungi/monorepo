# Dedicated scrape collector: a StatefulSet whose targetAllocator discovers the
# existing Prometheus Operator ServiceMonitor/PodMonitor CRs (prometheusCR mode)
# and hands their targets to the embedded prometheus receiver via http_sd. The
# operator rewires `receivers.prometheus` to the target allocator automatically
# when `targetAllocator.enabled = true` and a `prometheus` receiver is present.
#
# Exporter/extension inheritance: this collector intentionally does NOT redeclare
# `otlphttp/grafana-cloud` (exporter), `memory_limiter`/`batch` (processors), or
# `basicauth/grafana-cloud` (extension). The opentelemetry-kube-stack chart layers
# every collector on top of `defaultCRConfig` (= local.base_collector) -- the same
# inheritance the cluster_collector and daemon_collector pipelines already rely on
# (they reference these names without defining them). The merge is therefore
# confirmed, not assumed; see base_collector.tf for the definitions.
#
# targetAllocator schema is the OpenTelemetryCollector spec.targetAllocator field
# (sibling to mode/replicas/config), per opentelemetry-kube-stack 0.6.1 values.yaml.
# Empty-object selectors `{}` mean match-all (v1beta1 requires the keys be present
# even when empty); omitting them would match nothing.
locals {
  scrape_collector = {
    enabled  = true
    mode     = "statefulset"
    replicas = 1

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
        # Explicit empty objects = match ALL Pod/ServiceMonitors cluster-wide.
        podMonitorSelector     = {}
        serviceMonitorSelector = {}
        scrapeInterval         = "30s"
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
        # pipeline references resolve. memory_limiter + batch are defined there.
      }
      exporters = {
        # Inherited from base_collector: "debug" and "otlphttp/grafana-cloud".
      }
      service = {
        pipelines = {
          metrics = {
            receivers = [
              "prometheus",
            ]
            processors = [
              "memory_limiter",
              "batch",
            ]
            exporters = [
              "debug",
              "otlphttp/grafana-cloud",
            ]
          }
        }
      }
    }
  }
}
