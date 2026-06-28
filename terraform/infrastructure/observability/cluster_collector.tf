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
              # Grafana Cloud unrouted; synthetics already export to Honeycomb.
              "otlp/honeycomb-synthetics",
            ]
          }
          traces = null
        }
      }
    }
  }
}
