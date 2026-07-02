locals {
  cluster_collector = {
    # https://docs.honeycomb.io/send-data/kubernetes/values-files/values-deployment.yaml
    enabled  = true
    replicas = 1 # A deployment with exactly one replica ensures that we don’t produce duplicate data.
    # Pin ONLY the cluster collector to contrib 0.123.0 — a deliberate +3-minor
    # skew from the 0.120 operator default. tlscheckreceiver first shipped in the
    # PUBLISHED otel/opentelemetry-collector-contrib image at 0.123.0; 0.120/0.122
    # images lacked it despite repo source (upstream #38749, distribution-manifest gap).
    image = {
      repository = "otel/opentelemetry-collector-contrib"
      tag        = "0.123.0"
    }
    # Lean profile (see docs/right-sizing-resources.md). Single-replica deployment
    # running the k8sclusterreceiver + k8sobjectsreceiver; CPU limit omitted
    # fleet-wide (throttling hurts scrape/export timeliness).
    resources = {
      requests = {
        cpu    = "10m"
        memory = "128Mi"
      }
      limits = {
        memory = "160Mi"
      }
    }
    presets = {
      clusterMetrics = {
        # enables the k8sclusterreceiver and adds it to the metrics pipelines
        enabled = true
      }
      kubernetesEvents = {
        # enables the k8sobjectsreceiver to collect events only and adds it to the logs pipelines
        enabled = true
      }
    }
    config = {
      receivers = {
        k8s_cluster = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/k8sclusterreceiver/documentation.md
          # Honeycomb bills per datapoint. 300s (vs 30s) keeps ALL cluster series
          # intact (no metrics dropped) while emitting ~10x fewer datapoints.
          # Cluster-level resource counts change slowly; 5-minute resolution is ample.
          collection_interval = "300s"
          metrics = {
            # Disable replicaset metrics by default. These are typically high volume, low signal metrics.
            # If volume is not a concern, then the following blocks can be removed.
            "k8s.replicaset.desired" = {
              enabled = false
            }
            "k8s.replicaset.available" = {
              enabled = false
            }
          }
        }
        httpcheck = {
          targets = [
            {
              endpoint = "http://frank.sh"
            },
            {
              endpoint = "http://api.frank.sh/-/liveness"
            },
            {
              endpoint = "http://httpbin.frank.sh/ip"
            },
            {
              endpoint = "http://miniflux.frank.sh/healthcheck"
            }
          ]
          # Synthetic uptime checks do not need 15s resolution; 60s cuts the
          # httpcheck datapoint volume 4x while staying well within alerting SLOs.
          collection_interval = "60s"
        }
        tlscheck = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/tlscheckreceiver
          # Emits tlscheck.time_left (seconds until cert expiry). Targets use
          # endpoint host:port (no scheme). 300s is ample for SSL-expiry alerting.
          targets = [
            {
              endpoint = "frank.sh:443"
            },
            {
              endpoint = "api.frank.sh:443"
            },
            {
              endpoint = "httpbin.frank.sh:443"
            },
            {
              endpoint = "miniflux.frank.sh:443"
            }
          ]
          collection_interval = "300s"
        }
        "prometheus/self" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md
          # Per-collector liveness heartbeat (Option B): scrape THIS collector's
          # own internal Prometheus telemetry endpoint and stamp `collector =
          # cluster` so the three collectors are distinguishable in Grafana Cloud.
          # 127.0.0.1:8888 is in-container (same process as the collector's
          # telemetry server), so it resolves whether the internal endpoint binds
          # localhost or 0.0.0.0 across collector versions. base
          # service.telemetry.metrics.level = "normal" keeps otelcol_process_*
          # exposed; the metrics/self pipeline allowlists to that family via
          # filter/self-metrics. The cluster collector has NO targetAllocator, so
          # this receiver's static_configs are NOT rewritten by the operator.
          config = {
            scrape_configs = [
              {
                job_name        = "otelcol-self"
                scrape_interval = "60s"
                static_configs = [
                  {
                    targets = ["127.0.0.1:8888"]
                    labels = {
                      collector = "cluster"
                    }
                  },
                ]
              },
              {
                # Cross-scrape the SCRAPE collector's :8888 telemetry endpoint.
                # The scrape collector is a StatefulSet whose targetAllocator
                # rewrites any prometheus receiver's static_configs, so it
                # cannot self-scrape; we reach it here over its operator
                # monitoring Service instead. The cluster collector has NO
                # targetAllocator, so THIS receiver is left intact. An
                # unreachable remote target only marks the scrape stale in GC —
                # it does not crash this collector.
                job_name        = "otelcol-scrape"
                scrape_interval = "60s"
                static_configs = [
                  {
                    targets = ["opentelemetry-kube-stack-collector-collector-monitoring.observability.svc.cluster.local:8888"]
                    labels = {
                      collector = "scrape"
                    }
                  },
                ]
              },
            ]
          }
        }
      }
      processors = {
        "transform/k8s-events" = {
          error_mode = "ignore"
          log_statements = [
            {
              context = "log"
              statements = [
                # adds a new watch-type attribute from the body if it exists
                <<-EOT
                set(attributes["watch-type"], body["type"])
                where IsMap(body) and body["type"] != nil
                EOT
                ,
                # create new attributes from the body if the body is an object
                <<-EOT
                merge_maps(attributes, body, "upsert")
                where IsMap(body) and body["object"] == nil
                EOT
                ,
                <<-EOT
                merge_maps(attributes, body["object"], "upsert")
                where IsMap(body) and body["object"] != nil
                EOT
                ,
                # Transform the attributes so that the log events use the k8s.* semantic conventions
                <<-EOT
                merge_maps(attributes, attributes["metadata"], "upsert")
                where IsMap(attributes["metadata"])
                EOT
                ,
                <<-EOT
                set(attributes["k8s.pod.name"], attributes["regarding"]["name"])
                where attributes["regarding"]["kind"] == "Pod"
                EOT
                ,
                <<-EOT
                set(attributes["k8s.node.name"], attributes["regarding"]["name"])
                where attributes["regarding"]["kind"] == "Node"
                EOT
                ,
                <<-EOT
                set(attributes["k8s.job.name"], attributes["regarding"]["name"])
                where attributes["regarding"]["kind"] == "Job"
                EOT
                ,
                <<-EOT
                set(attributes["k8s.cronjob.name"], attributes["regarding"]["name"])
                where attributes["regarding"]["kind"] == "CronJob"
                EOT
                ,
                <<-EOT
                set(attributes["k8s.namespace.name"], attributes["regarding"]["namespace"])
                where attributes["regarding"]["kind"] == "Pod"
                or attributes["regarding"]["kind"] == "Job"
                or attributes["regarding"]["kind"] == "CronJob"
                EOT
                ,
                # Transform the type attributes into OpenTelemetry Severity types.
                <<-EOT
                set(severity_text, attributes["type"])
                where attributes["type"] == "Normal" or attributes["type"] == "Warning"
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_INFO)
                where attributes["type"] == "Normal"
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_WARN)
                where attributes["type"] == "Warning"
                EOT
                ,
              ]
            },
          ]
        }
      }
      exporters = {
        "otlp/honeycomb-k8s-events" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "k8s-events"
          })
        })
        "otlp/honeycomb-synthetics" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "synthetics"
          })
        })
      }
      service = {
        pipelines = {
          logs = {
            receivers = [
              "k8sobjects",
            ]
            processors = [
              "memory_limiter",
              "filter",
              "k8sattributes",
              "transform/k8s-events",
              "transform",
              # NOTE: "filter/logs" is intentionally OMITTED here. It lives in the
              # daemon logs pipeline (intended log-volume reduction). This cluster
              # pipeline carries k8s EVENTS (k8sobjects -> k8s-events dataset). The
              # filter's "service.name == nil -> drop INFO" fallback would drop all
              # Normal k8s events, which are low-volume (~611/day) and useful.
              "resourcedetection",
              "logdedup",
              "batch",
            ]
            exporters = [
              "debug",
              "otlp/honeycomb-k8s-events",
            ]
          }
          metrics = {
            receivers = [
              "k8s_cluster",
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
              # Grafana Cloud unrouted; curated cluster metrics now go to
              # Honeycomb (k8s-metrics dataset) via "filter/metrics-infra".
              "otlp/honeycomb-k8s-metrics",
            ]
          }
          "metrics/synthetics" = {
            receivers = [
              "httpcheck",
              "tlscheck",
            ]
            processors = [
              "memory_limiter",
              "batch",
            ]
            exporters = [
              "debug",
              # Dual-export synthetics (httpcheck + tlscheck) to BOTH backends.
              # Honeycomb remains the primary store; Grafana Cloud is re-routed
              # here (phase 1a) so GC alert rules can query synthetic
              # availability/latency/SSL-expiry. The "otlphttp/grafana-cloud"
              # exporter and "basicauth/grafana-cloud" extension are inherited
              # from defaultCRConfig (base_collector.tf) via the chart's
              # deep-merge; GC creds are injected by helm.tf extraEnvs.
              "otlp/honeycomb-synthetics",
              "otlphttp/grafana-cloud",
            ]
          }
          # Liveness heartbeat pipeline (Option B): self-scrape (:8888) ->
          # Grafana Cloud ONLY. memory_limiter, filter/self-metrics, and batch are
          # inherited from base_collector; otlphttp/grafana-cloud (exporter) and
          # basicauth/grafana-cloud (extension) are likewise inherited. Emits an
          # always-present otelcol_process_* series labelled collector=cluster so a
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
          traces = null
        }
      }
    }
  }
}
