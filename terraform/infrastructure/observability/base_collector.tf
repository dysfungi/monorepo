# https://opentelemetry.io/docs/platforms/kubernetes/getting-started/#overview
# https://github.com/open-telemetry/opentelemetry-operator/blob/main/docs/api/opentelemetrycollectors.md
# https://github.com/open-telemetry/opentelemetry-collector/blob/main/README.md
# https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/README.md
# https://docs.honeycomb.io/send-data/kubernetes/opentelemetry/create-telemetry-pipeline/#step-4-deploy-collectors
locals {
  backends = {
    otlp_honeycomb = {
      endpoint = "https://api.honeycomb.io:443"
      headers = {
        x-honeycomb-team = "$${env:HONEYCOMB_API_KEY}"
      }
    }
  }

  telemetry_backends = {
    # Headers have a different schema:
    #   headers  = [{name = "key", value = "value"}]
    otlp_honeycomb = merge(local.backends.otlp_honeycomb, {
      headers = [
        for key, value in local.backends.otlp_honeycomb.headers
        : {
          name  = key
          value = value
        }
      ]
      protocol = "http/protobuf"
    })
  }

  base_collector = {
    affinity = local.affinity
    ports = [
      {
        name       = "zpages"
        protocol   = "TCP"
        port       = 55679
        targetPort = 55679
      },
    ]
    config = {
      extensions = {
        health_check = {
          endpoint = ":13133"
        }
        # memory_limiter = {}
        zpages = {
          endpoint = ":55679"
        }
      }
      receivers = {
        filelog = {
          exclude = [
            # "/var/log/pods/${local.namespace}_opentelemetry-kube-stack-*_*/otc-container/*.log",
          ]
          operators = [
            { # Parse container logs.
              # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/container.md
              type         = "container"
              id           = "container-parser"
              max_log_size = 102400
            },
            { # Parse JSON body.
              # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/json_parser.md
              type       = "json_parser"
              parse_from = "body"
              parse_to   = "body"
              if         = <<-EOT
              body matches "^{[\\s\\S]+"
              EOT
              timestamp = {
                type        = "time_parser"
                parse_from  = "body.ts"
                layout_type = "strptime"
                layout      = "%Y-%m-%dT%H:%M:%S.%LZ"
              }
            },
          ]
        }
      }
      processors = {
        batch = {
          # https://github.com/open-telemetry/opentelemetry-collector/blob/main/processor/batchprocessor/README.md
        }
        filter = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/filterprocessor/README.md
          error_mode = "ignore"
          logs = {
            # log_record = ["true"]
          }
          metrics = {
            # metric    = ["true"]
            # datapoint = ["true"]
          }
          traces = {
            # span      = ["true"]
            # spanevent = ["true"]
          }
        }
        logdedup = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/logdedupprocessor/README.md
          # exclude_fields = ["uid"]
          include_fields = [
            "attributes.app",
            "attributes.body",
            "attributes.name",
            "attributes.service.name",
            "attributes.severity",
            "attributes.trace.span_id",
            "attributes.trace.trace_id",
            # "body",
          ]
          interval            = "60s"
          log_count_attribute = "log.dedupe.count"
        }
        memory_limiter = {
          # https://github.com/open-telemetry/opentelemetry-collector/blob/main/processor/memorylimiterprocessor/README.md
          check_interval   = "1s"
          limit_percentage = 85
        }
        probabilistic_sampler = {
          # Traces
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/probabilisticsamplerprocessor/README.md
          fail_closed         = true # Only disable to verify sampling failure
          hash_seed           = 22
          mode                = "proportional"
          sampling_percentage = 100
        }
        "probabilistic_sampler/logs" = {
          attribute_source    = "record"
          from_attribute      = "uid"
          fail_closed         = true # Only disable to verify sampling failure
          hash_seed           = 22
          mode                = "hash_seed"
          sampling_percentage = 50
        }
        "resourcedetection/env" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/resourcedetectionprocessor/README.md
          detectors = ["env"]
          timeout   = "1s"
          override  = false
        }
        transform = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/transformprocessor/README.md
          error_mode = "ignore"
          log_statements = [
            { # Transform body map
              context = "log"
              conditions = [
                "IsMap(body)",
              ]
              statements = [
                <<-EOT
                merge_maps(attributes, body, "upsert")
                where body["object"] == nil
                EOT
              ]
            },
            { # Add UID attribute.
              context = "log"
              statements = [
                <<-EOT
                set(attributes["uid"], UUID())
                where attributes["uid"] == nil
                EOT
                ,
              ]
            },
          ]
          metric_statements = []
          trace_statements  = []
        }
      }
      exporters = {
        debug = {
          # https://github.com/open-telemetry/opentelemetry-collector/blob/main/exporter/debugexporter/README.md
          # verbosity = "detailed"
        }
        otlp = local.backends.otlp_honeycomb
        "otlp/k8s-metrics" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "k8s-metrics"
          })
        })
      }
      service = {
        extensions = [
          "health_check",
          # "memory_limiter",
          "zpages",
        ]
        telemetry = {
          # https://opentelemetry.io/docs/collector/internal-telemetry/#activate-internal-telemetry-in-the-collector
          logs = {
            # https://opentelemetry.io/docs/collector/internal-telemetry/#configure-internal-logs
            # encoding = "console"
            encoding = "json"
            # level = "DEBUG"
            level = "INFO"
            # processors = [
            #   {
            #     batch = {
            #       exporter = {
            #         otlp = local.telemetry_backends.otlp_honeycomb
            #       }
            #     }
            #   },
            # ]
          }
          metrics = {
            # https://opentelemetry.io/docs/collector/internal-telemetry/#configure-internal-metrics
            level = "normal"
            # readers = [
            #   {
            #     periodic = {
            #       exporter = {
            #         otlp = local.telemetry_backends.otlp_honeycomb
            #       }
            #     }
            #   },
            # ]
          }
          traces = {
            # https://opentelemetry.io/docs/collector/internal-telemetry/#configure-internal-traces
            # processors = [
            #   {
            #     batch = {
            #       exporter = {
            #         otlp = local.telemetry_backends.otlp_honeycomb
            #       }
            #     }
            #   },
            # ]
          }
        }
      }
    }
  }
}
