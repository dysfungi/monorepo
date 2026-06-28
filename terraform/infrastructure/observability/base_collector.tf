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
          # Drop low-value, high-volume pod logs at the source (before any
          # processing/export). Calico alone accounted for ~29% of log volume;
          # the collector's own stdout, httpbin, and gpu-operator are similarly
          # noisy and low-signal. Paths mirror the chart's filelog `include`
          # glob form: /var/log/pods/<namespace>_<pod>_*/<container>/*.log.
          # Calico may run in either calico-system or kube-system, so both are
          # matched.
          exclude = [
            "/var/log/pods/calico-system_*/*/*.log",
            "/var/log/pods/kube-system_*calico*/*/*.log",
            "/var/log/pods/${local.namespace}_*opentelemetry*/*/*.log",
            "/var/log/pods/httpbin_*/*/*.log",
            "/var/log/pods/gpu-operator_*/*/*.log",
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
        "filter/logs" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/filterprocessor/README.md
          # Drop INFO/DEBUG records for the highest-volume services while
          # preserving low-volume INFO elsewhere. A record is dropped when ANY
          # listed OTTL condition is true. severity_number == 0 (unset/
          # unclassified) is explicitly KEPT so unparsed logs are never silently
          # discarded. Must run after k8sattributes/transform so service.name is
          # populated on the resource.
          error_mode = "ignore"
          logs = {
            log_record = [
              <<-EOT
              severity_number != 0 and severity_number < SEVERITY_NUMBER_WARN and (resource.attributes["service.name"] == "automate" or resource.attributes["service.name"] == "nginx-gateway-fabric" or resource.attributes["service.name"] == "prod-web-nginx")
              EOT
              ,
              # Fallback for records without a service.name (e.g. raw k8s pod
              # logs in the k8s-logs dataset and Normal k8s events): drop
              # INFO/DEBUG, keep WARN+ and unclassified.
              <<-EOT
              severity_number != 0 and severity_number < SEVERITY_NUMBER_WARN and resource.attributes["service.name"] == nil
              EOT
              ,
            ]
          }
        }
        "filter/metrics-infra" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/filterprocessor/README.md
          # Allowlist: keep only a deliberately tiny set of infra metrics
          # (kubeletstats + k8s_cluster) and drop everything else to protect the
          # Honeycomb event budget. A metric is dropped when the condition is
          # true, so we drop everything NOT in the allowed set.
          # kubeletstats v0.120 renamed the CPU metrics utilization -> usage; the
          # allowlist tracks the current names (k8s.node.cpu.usage /
          # k8s.pod.cpu.usage). hostMetrics `system.*` are intentionally NOT in
          # this allowlist -- node-level CPU/memory are already covered by
          # kubeletstats `k8s.node.*`, so `system.*` are dropped before export.
          error_mode = "ignore"
          # OTTL metric context uses `name`, not `metric.name`.
          metrics = {
            metric = [
              <<-EOT
              not (name == "k8s.node.cpu.usage" or name == "k8s.node.memory.usage" or name == "k8s.pod.cpu.usage" or name == "k8s.pod.memory.usage" or name == "k8s.container.restarts" or name == "k8s.pod.phase")
              EOT
              ,
            ]
          }
        }
        "filter/metrics-dotnet" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/filterprocessor/README.md
          # Allowlist for the scrape collector: keep only the .NET runtime
          # exception counter scraped from the automate-api PodMonitor and drop
          # all other scraped Prometheus metrics.
          error_mode = "ignore"
          metrics = {
            metric = [
              <<-EOT
              not IsMatch(name, "systemruntime_exception_count")
              EOT
              ,
            ]
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
          sampling_percentage = 20
        }
        # NOTE: "probabilistic_sampler/logs" was intentionally removed. In
        # hash_seed mode it dropped ~50% of log records WITHOUT writing a
        # Honeycomb SampleRate attribute, so the surviving records billed as
        # unsampled and the drop was invisible to queries (misleading volume +
        # broken counts). Log volume is now reduced explicitly via filelog
        # `exclude` and "filter/logs" instead.
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
        "transform/severity" = {
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/transformprocessor/README.md
          # Classify records that arrive with severity_number == 0 so the
          # downstream "filter/logs" (drop INFO/DEBUG for high-volume services)
          # can act on them. Two source services dominate the unclassified
          # volume: the "automate" app and raw k8s pod logs (k8s-logs dataset,
          # no service.name). MUST run AFTER k8sattributes/transform (so
          # resource.attributes["service.name"] is populated) and BEFORE
          # "filter/logs". Every set() is guarded with `severity_number == 0`
          # so an already-classified record is never downgraded, and each set
          # is scoped by service.name so the per-format regexes cannot mis-tag
          # another service's records. error_mode = "ignore" means a runtime
          # type mismatch (e.g. IsMatch on a non-string body) is skipped, not
          # fatal -- consistent with every other transform here.
          error_mode = "ignore"
          log_statements = [
            {
              context = "log"
              statements = [
                # --- automate: structured JSON logs (~3.7%) ---
                # The container/json operators land the level in
                # attributes["log.body.LogLevel"] (.NET Microsoft.Extensions
                # logging level names). Map directly; no body string needed.
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_TRACE) where resource.attributes["service.name"] == "automate" and severity_number == 0 and attributes["log.body.LogLevel"] == "Trace"
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_DEBUG) where resource.attributes["service.name"] == "automate" and severity_number == 0 and attributes["log.body.LogLevel"] == "Debug"
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_INFO) where resource.attributes["service.name"] == "automate" and severity_number == 0 and attributes["log.body.LogLevel"] == "Information"
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_WARN) where resource.attributes["service.name"] == "automate" and severity_number == 0 and attributes["log.body.LogLevel"] == "Warning"
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_ERROR) where resource.attributes["service.name"] == "automate" and severity_number == 0 and attributes["log.body.LogLevel"] == "Error"
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_FATAL) where resource.attributes["service.name"] == "automate" and severity_number == 0 and attributes["log.body.LogLevel"] == "Critical"
                EOT
                ,
                # --- automate: plain-text prefix logs (~48%) ---
                # ASP.NET console formatter prefixes each header line with a
                # 4-char level token + ": " (info:, warn:, fail:, crit:, dbug:,
                # trce:). Match on the leading token.
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_TRACE) where resource.attributes["service.name"] == "automate" and severity_number == 0 and IsMatch(body, "^trce: ")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_DEBUG) where resource.attributes["service.name"] == "automate" and severity_number == 0 and IsMatch(body, "^dbug: ")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_INFO) where resource.attributes["service.name"] == "automate" and severity_number == 0 and IsMatch(body, "^info: ")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_WARN) where resource.attributes["service.name"] == "automate" and severity_number == 0 and IsMatch(body, "^warn: ")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_ERROR) where resource.attributes["service.name"] == "automate" and severity_number == 0 and IsMatch(body, "^fail: ")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_FATAL) where resource.attributes["service.name"] == "automate" and severity_number == 0 and IsMatch(body, "^crit: ")
                EOT
                ,
                # --- automate: continuation lines (~48%) ---
                # The ASP.NET formatter emits the message body on the NEXT line,
                # indented with spaces and carrying no level token, so it stays
                # at severity_number == 0 (kept, not dropped). Recombining a
                # continuation line with its header is a multiline-recombine
                # problem deferred to a future change; intentionally NOT handled
                # here.
                # --- k8s-logs: klog format (~77%) ---
                # Records with no service.name are the raw k8s pod logs in the
                # k8s-logs dataset. klog lines begin with a single severity
                # letter: I=INFO, W=WARN, E=ERROR, F=FATAL. The service.name ==
                # nil guard keeps these single-letter regexes from tagging
                # automate or any other service.
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_INFO) where resource.attributes["service.name"] == nil and severity_number == 0 and IsMatch(body, "^I")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_WARN) where resource.attributes["service.name"] == nil and severity_number == 0 and IsMatch(body, "^W")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_ERROR) where resource.attributes["service.name"] == nil and severity_number == 0 and IsMatch(body, "^E")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_FATAL) where resource.attributes["service.name"] == nil and severity_number == 0 and IsMatch(body, "^F")
                EOT
                ,
                # --- k8s-logs: logfmt format (~22%) ---
                # logfmt lines carry an inline `level=<sev>` field anywhere in
                # the body.
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_INFO) where resource.attributes["service.name"] == nil and severity_number == 0 and IsMatch(body, "level=info")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_WARN) where resource.attributes["service.name"] == nil and severity_number == 0 and IsMatch(body, "level=warn")
                EOT
                ,
                <<-EOT
                set(severity_number, SEVERITY_NUMBER_ERROR) where resource.attributes["service.name"] == nil and severity_number == 0 and IsMatch(body, "level=error")
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
        # Intentionally defined but not routed to any pipeline; re-add to a
        # pipeline's exporters array to re-enable Grafana Cloud. The
        # "basicauth/grafana-cloud" extension and its secret/creds are likewise
        # kept intact so this is a one-line re-enable.
        "otlphttp/grafana-cloud" = local.backends.otlphttp_grafana_cloud
        "otlp/honeycomb"         = local.backends.otlp_honeycomb
        "otlp/honeycomb-k8s-metrics" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "k8s-metrics"
          })
        })
        "otlp/honeycomb-synthetics" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "synthetics"
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
