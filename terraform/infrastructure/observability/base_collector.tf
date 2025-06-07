# https://opentelemetry.io/docs/platforms/kubernetes/getting-started/#overview
# https://github.com/open-telemetry/opentelemetry-operator/blob/main/docs/api/opentelemetrycollectors.md
# https://github.com/open-telemetry/opentelemetry-collector/blob/main/README.md
# https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/README.md
# https://docs.honeycomb.io/send-data/kubernetes/opentelemetry/create-telemetry-pipeline/#step-4-deploy-collectors
# https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/collector/opentelemetry-collector/#advanced-manual-setup
locals {
  backends = {
    otlphttp_grafana_cloud = {
      # https://grafana.com/orgs/fungi/stacks/1282220/otlp-info
      # https://grafana.com/docs/grafana-cloud/send-data/otlp/
      # https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/collector/opentelemetry-collector/
      endpoint = "https://otlp-gateway-prod-us-west-0.grafana.net/otlp"
      auth = {
        authenticator = "basicauth/grafana-cloud"
      }
    }
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
      connectors = {
        # grafanacloud = {
        #   # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/grafanacloudconnector
        #   host_identifiers = ["host.name"]
        # }
      }
      extensions = {
        "basicauth/grafana-cloud" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/extension/basicauthextension
          client_auth = {
            username = "$${env:GRAFANA_CLOUD_INSTANCE_ID}"
            password = "$${env:GRAFANA_CLOUD_API_KEY}"
          }
        }
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
              id           = "container-parser"
              max_log_size = 102400
              type         = "container"
            },
            # Parse regex body.
            {
              id         = "regex-parser:body:calico-node"
              if         = <<-EOT
              attributes["log.file.path"] startsWith "/var/log/pods/kube-system_calico-"
              EOT
              parse_from = "body"
              parse_to   = "attributes.log.body"
              # example: 2025-06-02 00:32:42.687 [INFO][49] felix/int_dataplane.go 2201: Received *proto.HostMetadataV4V6Update update from calculation graph.
              regex = "^(?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}.\\d+) \\[(?P<level>[A-Z]+)\\](?P<msg>.+)$"
              severity = {
                parse_from = "attributes.log.body.level"
              }
              timestamp = {
                layout      = "%Y-%m-%d %H:%M:%S.%L"
                layout_type = "strptime"
                parse_from  = "attributes.log.body.timestamp"
              }
              type = "regex_parser"
            },
            {
              id         = "regex-parser:body:httpbin"
              if         = <<-EOT
              attributes["log.file.path"] startsWith "/var/log/pods/httpbin_httpbin-"
              EOT
              parse_from = "body"
              parse_to   = "attributes.http"
              # example: time="2025-06-01T21:36:43.7986" status=200 method="GET" uri="/status/200" size_bytes=0 duration_ms=0.06
              regex = "^time=\"(?P<timestamp>\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}.\\d+)\" status=(?P<status_code>\\d+) method=\"(?P<method>[A-Z]+)\" uri=\"(?P<target>.+)\" size_bytes=(?P<response_content_length>\\d+) duration_ms=(?P<duration_ms>\\d+\\.\\d+)$"
              severity = {
                mapping = {
                  info = ["0", "2xx", "3xx", "4xx", "5xx"]
                }
                parse_from = "attributes.http.status_code"
              }
              timestamp = {
                layout      = "%Y-%m-%dT%H:%M:%S.%L"
                layout_type = "strptime"
                parse_from  = "attributes.http.timestamp"
              }
              type = "regex_parser"
            },
            # Parse JSON body.
            # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/json_parser.md
            {
              id         = "json-parser:body"
              if         = <<-EOT
              body matches "^{[\\s\\S]+"
              EOT
              parse_from = "body"
              parse_to   = "attributes.log.body"
              type       = "json_parser"
            },
            # Parse severity
            {
              id         = "severity-parser:body.level"
              if         = "attributes.log?.body?.level != nil"
              parse_from = "attributes.log.body.level"
              type       = "severity_parser"
            },
            # Parse timestamp
            {
              id          = "timestamp-parser:body.Timestamp:as-rfc-3339-utc"
              if          = <<-EOT
              type(attributes.log?.body?.Timestamp) == "string"
              EOT
              layout      = "%Y-%m-%dT%H:%M:%S.%LZ"
              layout_type = "strptime"
              parse_from  = "attributes.log.body.Timestamp"
              type        = "time_parser"
            },
            {
              id          = "timestamp-parser:body.time:as-rfc-3339-tz"
              if          = <<-EOT
              type(attributes.log?.body?.time) == "string"
              EOT
              layout      = "%Y-%m-%dT%H:%M:%S.%L%j"
              layout_type = "strptime"
              parse_from  = "attributes.log.body.time"
              type        = "time_parser"
            },
            {
              id          = "timestamp-parser:body.timestamp:as-rfc-3339-utc"
              if          = <<-EOT
              type(attributes.log?.body?.timestamp) == "string"
              && attributes.log.body.timestamp endsWith "Z"
              EOT
              layout      = "%Y-%m-%dT%H:%M:%SZ"
              layout_type = "strptime"
              parse_from  = "attributes.log.body.timestamp"
              type        = "time_parser"
            },
            {
              id          = "timestamp-parser:body.ts:as-epoch"
              if          = <<-EOT
              type(attributes.log?.body?.ts) == "float"
              EOT
              layout      = "s.us"
              layout_type = "epoch"
              parse_from  = "attributes.log.body.ts"
              type        = "time_parser"
            },
            {
              id          = "timestamp-parser:body.ts:as-rfc-3339-ms-utc"
              if          = <<-EOT
              type(attributes.log?.body?.ts) == "string"
              && attributes.log.body.ts matches "\\.\\d+Z$"
              EOT
              layout      = "%Y-%m-%dT%H:%M:%S.%LZ"
              layout_type = "strptime"
              parse_from  = "attributes.log.body.ts"
              type        = "time_parser"
            },
            {
              id          = "timestamp-parser:body.ts:as-rfc-3339-s-utc"
              if          = <<-EOT
              type(attributes.log?.body?.ts) == "string"
              && attributes.log.body.ts matches ":\\d{2}Z$"
              EOT
              layout      = "%Y-%m-%dT%H:%M:%SZ"
              layout_type = "strptime"
              parse_from  = "attributes.log.body.ts"
              type        = "time_parser"
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
          interval            = "10s"
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
        resourcedetection = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/resourcedetectionprocessor/README.md
          detectors = ["env", "system"]
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
                ,
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
          trace_statements = [
            {
              context = "span"
              conditions = [
                <<-EOT
                attributes["http"]["target"] != nil
                EOT
                ,
              ]
              statements = [
                <<-EOT
                set(attributes["http.fragment"], ExtractPatterns(attributes["http"]["target"], "[#](?P<fragment>[^?]*)([?].*)?$")["fragment"])
                where attributes["http"]["target"] != nil
                EOT
                ,
                <<-EOT
                set(attributes["http.path"], ExtractPatterns(attributes["http"]["target"], "^(?P<path>[^?#]+)")["path"])
                where attributes["http"]["target"] != nil
                EOT
                ,
                <<-EOT
                set(attributes["http.query"], ExtractPatterns(attributes["http"]["target"], "[?](?P<query>[^#]*)([#].*)?$")["query"])
                where attributes["http"]["target"] != nil
                EOT
                ,
              ]
            },
          ]
        }
        "transform/drop_unneeded_resource_attributes" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/transformprocessor
          error_mode = "ignore"
          trace_statements = [
            {
              context = "resource"
              statements = [
                <<-EOT
                delete_key(attributes, "k8s.pod.start_time")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "os.description")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "os.type")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.command_args")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.executable.path")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.pid")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.description")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.name")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.version")
                EOT
                ,
              ]
            },
          ]
          metric_statements = [
            {
              context = "resource"
              statements = [
                <<-EOT
                delete_key(attributes, "k8s.pod.start_time")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "os.description")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "os.type")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.command_args")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.executable.path")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.pid")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.description")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.name")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.version")
                EOT
                ,
              ]
            },
          ]
          log_statements = [
            {
              context = "resource"
              statements = [
                <<-EOT
                delete_key(attributes, "k8s.pod.start_time")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "os.description")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "os.type")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.command_args")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.executable.path")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.pid")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.description")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.name")
                EOT
                ,
                <<-EOT
                delete_key(attributes, "process.runtime.version")
                EOT
                ,
              ]
            },
          ]
        }
        "transform/add_resource_attributes_as_metric_attributes" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/transformprocessor
          error_mode = "ignore"
          metric_statements = [
            {
              context = "datapoint"
              statements = [
                <<-EOT
                set(attributes["deployment.environment"], resource.attributes["deployment.environment"])
                EOT
                ,
                <<-EOT
                set(attributes["service.version"], resource.attributes["service.version"])
                EOT
                ,
              ]
            },
          ]
        }
      }
      exporters = {
        debug = {
          # https://github.com/open-telemetry/opentelemetry-collector/blob/main/exporter/debugexporter/README.md
          # verbosity = "detailed"
        }
        "otlphttp/grafana-cloud" = local.backends.otlphttp_grafana_cloud
        "otlp/honeycomb"         = local.backends.otlp_honeycomb
        "otlp/honeycomb-k8s-metrics" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "k8s-metrics"
          })
        })
      }
      service = {
        extensions = [
          "basicauth/grafana-cloud",
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
