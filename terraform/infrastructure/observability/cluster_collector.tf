locals {
  cluster_collector = {
    # https://docs.honeycomb.io/send-data/kubernetes/values-files/values-deployment.yaml
    enabled  = true
    replicas = 1 # A deployment with exactly one replica ensures that we don’t produce duplicate data.

    # DELIBERATE VERSION SKEW (cluster collector ONLY): override the image onto
    # the contrib distro at 0.122.0. Two independent reasons, both verified
    # against upstream source rather than assumed:
    #   1. Distro: the operator-default otel/opentelemetry-collector-k8s distro
    #      does NOT bundle the tlscheck receiver; contrib does. The chart renders
    #      this {repository,tag} map into the OpenTelemetryCollector CR's
    #      spec.image string as "<repository>:<tag>"
    #      (opentelemetry-kube-stack templates/collector.yaml).
    #   2. Version: tlscheck was only added to the contrib *distribution build*
    #      (cmd/otelcontribcol/builder-config.yaml) at v0.122.0. At v0.118-0.121
    #      the receiver source dir existed but was NOT compiled into the released
    #      image -- which is why the earlier contrib:0.120.0 attempt crashlooped
    #      with `unknown type: "tlscheck"`. 0.122.0 is the MINIMUM image that
    #      actually contains the receiver, so skew from the 0.120.0 fleet is kept
    #      to +2 minors. daemon/scrape collectors stay on the k8s distro to
    #      minimize blast radius.
    image = {
      repository = "otel/opentelemetry-collector-contrib"
      tag        = "0.122.0"
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
          collection_interval = "30s"
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
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.122.0/receiver/tlscheckreceiver/README.md
          # SSL/TLS certificate-expiry monitoring. Requires the contrib distro at
          # >= 0.122.0 (see the `image` override above); the k8s distro lacks this
          # receiver and contrib only compiled it into the released image at
          # 0.122.0. Emits ONE gauge per target, `tlscheck.time_left` (seconds
          # until the x.509 NotAfter; negative once expired).
          #
          # SCHEMA NOTE: as of 0.122.0 each target is a TCP address -- `endpoint`
          # is "host:port" with NO scheme (a "://" scheme is rejected at config
          # validation). This differs from the pre-0.122 `url` field; since the
          # only image that actually ships the receiver is >= 0.122.0, the
          # host:port form is the correct (and only) option. 443 is the TLS port.
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
          # Cert expiry is slow-moving, so a long 300s interval keeps datapoint
          # volume tiny.
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
              # tlscheck (cert-expiry, `tlscheck.time_left`) mirrors httpcheck
              # exactly: same pipeline, same exporter. This pipeline has NO
              # metric-name filter (no "filter/metrics-infra"), so the tlscheck
              # metric is not dropped on export.
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
