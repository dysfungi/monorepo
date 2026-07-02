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

    # Lean profile (see docs/right-sizing-resources.md). Discovery for the embedded
    # `prometheus` receiver is scoped to the single automate-api PodMonitor
    # (targetAllocator.prometheusCR below), so its footprint is small -- 7-day actuals
    # sit well under 64Mi, which is why the earlier 512Mi anti-OOM ceiling is no longer
    # needed. Request stays at 64Mi (scheduling reservation stays lean). The LIMIT was
    # raised 64->128Mi because this collector now ALSO runs the full-cluster
    # `prometheus/cadvisor` scrape (added below): /metrics/cadvisor is a large per-node
    # payload, and even though metric_relabel_configs keeps only 3 series, the raw
    # payload is transiently parsed before the keep filter applies -- the extra ceiling
    # is burst headroom for that parse. CPU request at the fleet floor; CPU limit
    # omitted (throttling hurts scrape timeliness).
    resources = {
      requests = {
        cpu    = "10m"
        memory = "64Mi"
      }
      limits = {
        memory = "128Mi"
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
      # Lean profile (see docs/right-sizing-resources.md). The allocator only tracks
      # the single automate PodMonitor's targets, so its footprint is minimal. Limit
      # raised 64->96Mi for headroom (observed ~85% of the old 64Mi limit while fresh;
      # within the documented 64-96Mi range). Request stays 64Mi.
      resources = {
        requests = {
          cpu    = "10m"
          memory = "64Mi"
        }
        limits = {
          memory = "96Mi"
        }
      }
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
            "app.kubernetes.io/component" = "match-nothing"
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
        "prometheus/cadvisor" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md
          # cAdvisor scrape for CPU throttling (container_cpu_cfs_throttled_*), the
          # #1 CPU-saturation signal, routed to Grafana Cloud (metrics/cadvisor
          # pipeline). cAdvisor is exposed by every node's kubelet at
          # /metrics/cadvisor; kubernetes_sd role=node discovers the nodes and the
          # default __address__ is the kubelet (<node>:10250), so this is a DIRECT
          # kubelet scrape -- authorized by the collector SA's `nodes/metrics` RBAC
          # (scrape_collector_rbac.tf), exactly what that permission set was added
          # for. Bearer token + CA come from the auto-mounted SA; insecure_skip_verify
          # mirrors the daemon kubeletstats TLS setting (kubelet serving certs are not
          # in the SA CA bundle).
          #
          # TA SAFETY: this is a SEPARATE receiver named `prometheus/cadvisor`. The
          # operator's targetAllocator rewrites ONLY the receiver keyed exactly
          # `prometheus` (verified in operator source v0.120.0: config_to_prom_config.go
          # does `receivers["prometheus"]`, an exact map-key lookup, and config_replace.go
          # writes back that one key). Sibling `prometheus/<suffix>` receivers are left
          # intact -- so this static scrape_configs is NOT clobbered by the allocator.
          # (Supersedes the older, over-cautious "rewrites any prometheus receiver"
          # note in cluster_collector.tf; the daemon/cluster prometheus/self receivers
          # already rely on the same exact-key contract.)
          config = {
            scrape_configs = [
              {
                job_name        = "kubelet-cadvisor"
                scheme          = "https"
                metrics_path    = "/metrics/cadvisor"
                scrape_interval = "60s"
                authorization = {
                  type             = "Bearer"
                  credentials_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
                }
                tls_config = {
                  ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                  insecure_skip_verify = true
                }
                kubernetes_sd_configs = [
                  {
                    role = "node"
                  },
                ]
                relabel_configs = [
                  {
                    action = "labelmap"
                    regex  = "__meta_kubernetes_node_label_(.+)"
                  },
                ]
                # Bound receiver memory: /metrics/cadvisor is a large full-node payload,
                # but only the CFS throttle family survives the metrics/cadvisor pipeline
                # (filter/metrics-cadvisor). KEEP just those 3 series at scrape time so the
                # full payload never enters the pipeline. Names mirror filter/metrics-cadvisor
                # in base_collector.tf exactly (defense-in-depth: both agree).
                metric_relabel_configs = [
                  {
                    source_labels = ["__name__"]
                    regex         = "container_cpu_cfs_(throttled_periods_total|throttled_seconds_total|periods_total)"
                    action        = "keep"
                  },
                ]
              },
            ]
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
          # cAdvisor throttling pipeline: prometheus/cadvisor (receiver) -> Grafana
          # Cloud ONLY. Separate from the "metrics" pipeline above because it has a
          # different receiver (a static kubelet scrape, NOT target-allocated) and a
          # different allowlist. filter/metrics-cadvisor keeps only the
          # container_cpu_cfs_throttled_* family; otlphttp/grafana-cloud,
          # memory_limiter, and batch are inherited from base_collector.
          "metrics/cadvisor" = {
            receivers = [
              "prometheus/cadvisor",
            ]
            processors = [
              "memory_limiter",
              "filter/metrics-cadvisor",
              "batch",
            ]
            exporters = [
              "otlphttp/grafana-cloud",
            ]
          }
        }
      }
    }
  }
}
