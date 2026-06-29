locals {
  daemon_collector = {
    # https://docs.honeycomb.io/send-data/kubernetes/values-files/values-daemonset.yaml
    enabled = true
    # https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-kube-stack#scrape_configs_file-details
    scrape_configs_file = "" # Disable Prometheus scraping
    presets = {
      hostMetrics = {
        enabled = true
      }
      kubeletMetrics = {
        # enables the kubeletstatsreceiver and adds it to the metrics pipelines
        enabled = true
      }
      kubernetesAttributes = {
        # enables the k8sattributesprocessor and adds it to the traces, metrics, and logs pipelines
        enabled                  = true
        extractAllPodLabels      = true
        extractAllPodAnnotations = true
      }
      logsCollection = {
        enabled              = true
        includeCollectorLogs = false
      }
    }
    # https://github.com/open-telemetry/opentelemetry-helm-charts/blob/main/charts/opentelemetry-kube-stack/daemon_scrape_configs.yaml
    # scrape_configs_file = "daemon_scrape_configs.yaml"
    config = {
      receivers = {
        kubeletstats = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/kubeletstatsreceiver/documentation.md
          insecure_skip_verify = true
          # Honeycomb bills per datapoint. 300s (vs 30s) keeps ALL series intact
          # (no metrics dropped) while emitting ~10x fewer datapoints. Node/pod/
          # container resource gauges change slowly; 5-minute resolution is ample.
          collection_interval = "300s"
          metric_groups       = ["node", "pod", "container"]
          metrics = {
            "k8s.node.uptime" = {
              enabled = true
            }
            "k8s.pod.uptime" = {
              enabled = true
            }
            "k8s.pod.cpu_limit_utilization" = {
              enabled = true
            }
            "k8s.pod.cpu_request_utilization" = {
              enabled = true
            }
            "k8s.pod.memory_limit_utilization" = {
              enabled = true
            }
            "k8s.pod.memory_request_utilization" = {
              enabled = true
            }
          }
        }
        otlp = {
          # https://github.com/open-telemetry/opentelemetry-collector/blob/main/receiver/otlpreceiver/README.md
          protocols = {
            grpc = {
              endpoint = "0.0.0.0:4317"
            }
            http = {
              endpoint = "0.0.0.0:4318"
            }

          }
        }
        "prometheus/self" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md
          # Per-collector liveness heartbeat (Option B): scrape THIS collector's
          # own internal Prometheus telemetry endpoint and stamp `collector =
          # daemon` so the three collectors are distinguishable in Grafana Cloud.
          # 127.0.0.1:8888 is in-container (same process as the collector's
          # telemetry server), so it resolves whether the internal endpoint binds
          # localhost or 0.0.0.0 across collector versions. base
          # service.telemetry.metrics.level = "normal" keeps otelcol_process_*
          # exposed; the metrics/self pipeline allowlists to that family via
          # filter/self-metrics. No targetAllocator on the daemon, so this
          # receiver's static_configs are NOT rewritten by the operator.
          config = {
            scrape_configs = [
              {
                job_name        = "otelcol-self"
                scrape_interval = "60s"
                static_configs = [
                  {
                    targets = ["127.0.0.1:8888"]
                    labels = {
                      collector = "daemon"
                    }
                  },
                ]
              },
            ]
          }
        }
      }
      connectors = {
        spanmetrics = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/spanmetricsconnector
          # Derive gateway RED metrics (calls + duration histogram) from the
          # nginx-gateway-fabric OTLP traces this daemon already receives. The
          # connector is fed by the daemon traces pipeline (listed as an exporter
          # there) and emits into the "metrics/spanmetrics" pipeline (listed as a
          # receiver there), which exports to Grafana Cloud where the gateway
          # error-rate + latency alert rules live. Honeycomb keeps the raw spans.
          # Scoped to the daemon (only collector receiving gateway traces); a
          # connector defined but unused in a pipeline crashes the collector, so
          # it is intentionally NOT placed in base_collector (cluster/scrape have
          # no traces pipeline to consume it).
          # CAVEAT: this connector sits on the POST-sampler traces pipeline (20%
          # probabilistic_sampler, proportional mode), so call COUNTS are ~1/5 of
          # actual throughput; error-rate ratios and latency percentiles remain
          # representative under uniform random sampling.
          histogram = {
            # Web-latency buckets (request durations).
            explicit = {
              buckets = ["5ms", "10ms", "25ms", "50ms", "100ms", "250ms", "500ms", "1s", "2.5s", "5s"]
            }
          }
          # service.name, span.name, span.kind, status.code are dimensions by
          # default; add the gateway HTTP attributes. Verified in Honeycomb that
          # gateway spans carry `http.status_code` (NOT http.response.status_code).
          dimensions = [
            { name = "http.status_code" },
            { name = "http.method" },
          ]
        }
      }
      processors = {}
      exporters = {
        "otlp/honeycomb-k8s-logs" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "k8s-logs"
          })
        })
      }
      service = {
        pipelines = {
          logs = {
            receivers = [
              "otlp",
            ]
            processors = [
              "memory_limiter",
              "filter",
              "k8sattributes",
              "transform",
              # Classify severity_number for automate + k8s-logs records that
              # arrive at 0, so "filter/logs" (next) can drop their INFO/DEBUG.
              # Ordered after k8sattributes (needs service.name) and before
              # filter/logs.
              "transform/severity",
              "filter/logs",
              "resourcedetection",
              "logdedup",
              "batch",
            ]
            exporters = [
              "debug",
              "otlp/honeycomb-k8s-logs",
            ]
          }
          metrics = {
            receivers = [
              "otlp",
            ]
            processors = [
              "memory_limiter",
              "filter",
              "k8sattributes",
              "transform",
              "transform/drop_unneeded_resource_attributes",
              "transform/add_resource_attributes_as_metric_attributes",
              "filter/metrics-infra",
              "resourcedetection",
              "batch",
            ]
            exporters = [
              "debug",
              # Grafana Cloud unrouted; curated infra metrics now go to Honeycomb
              # (k8s-metrics dataset) via the "filter/metrics-infra" allowlist.
              "otlp/honeycomb-k8s-metrics",
            ]
          }
          traces = {
            receivers = [
              "otlp",
            ]
            processors = [
              "memory_limiter",
              "filter",
              "k8sattributes",
              "transform",
              "resourcedetection",
              "probabilistic_sampler",
              "batch",
            ]
            exporters = [
              "debug",
              "otlp/honeycomb",
              # Tee gateway spans into the spanmetrics connector to derive RED
              # metrics; raw spans still flow to Honeycomb via otlp/honeycomb.
              "spanmetrics",
            ]
          }
          # RED metrics pipeline: spanmetrics connector (receiver) → Grafana
          # Cloud ONLY. Kept separate from the kubeletstats "metrics" pipeline
          # above (different receiver + exporter). GC hosts the gateway
          # error-rate and latency alert rules; Honeycomb retains the raw spans
          # (daemon·traces). memory_limiter + batch are inherited from
          # base_collector processors.
          "metrics/spanmetrics" = {
            receivers = [
              "spanmetrics",
            ]
            processors = [
              "memory_limiter",
              "batch",
            ]
            exporters = [
              "otlphttp/grafana-cloud",
            ]
          }
          # Liveness heartbeat pipeline (Option B): self-scrape (:8888) ->
          # Grafana Cloud ONLY. memory_limiter, filter/self-metrics, and batch are
          # inherited from base_collector; otlphttp/grafana-cloud (exporter) and
          # basicauth/grafana-cloud (extension) are likewise inherited. Emits an
          # always-present otelcol_process_* series labelled collector=daemon so a
          # GC deadman alert can detect this collector going silent.
          "metrics/self" = {
            receivers = [
              "prometheus/self",
            ]
            processors = [
              "memory_limiter",
              "filter/self-metrics",
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
