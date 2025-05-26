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
      receivers = {}
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
          interval            = "60s"
          log_count_attribute = "log_count"
          conditions          = ["true"]
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
          from_attribute      = "first_observed_timestamp"
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
          error_mode        = "ignore"
          log_statements    = []
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
            level = "DEBUG"
            processors = [
              {
                batch = {
                  exporter = {
                    otlp = local.telemetry_backends.otlp_honeycomb
                  }
                }
              },
            ]
          }
          metrics = {
            # https://opentelemetry.io/docs/collector/internal-telemetry/#configure-internal-metrics
            level = "normal"
            readers = [
              {
                periodic = {
                  exporter = {
                    otlp = local.telemetry_backends.otlp_honeycomb
                  }
                }
              },
            ]
          }
          traces = {
            # https://opentelemetry.io/docs/collector/internal-telemetry/#configure-internal-traces
            processors = [
              {
                batch = {
                  exporter = {
                    otlp = local.telemetry_backends.otlp_honeycomb
                  }
                }
              },
            ]
          }
        }
      }
    }
  }

  deployment_collector = {
    # https://docs.honeycomb.io/send-data/kubernetes/values-files/values-deployment.yaml
    enabled  = true
    replicas = 1 # A deployment with exactly one replica ensures that we don’t produce duplicate data.
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
        "otlp/k8s-events" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "k8s-events"
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
              "logdedup",
              "probabilistic_sampler/logs",
              "k8sattributes",
              "resourcedetection/env",
              "transform/k8s-events",
              "batch",
            ]
            exporters = [
              "debug",
              "otlp/k8s-events",
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
              "resourcedetection/env",
              "batch",
            ]
            exporters = [
              "debug",
              # "otlp/k8s-metrics",
            ]
          }
          traces = null
        }
      }
    }
  }

  daemonset_collector = {
    # https://docs.honeycomb.io/send-data/kubernetes/values-files/values-daemonset.yaml
    enabled = true
    presets = {
      kubernetesAttributes = {
        # enables the k8sattributesprocessor and adds it to the traces, metrics, and logs pipelines
        enabled                  = true
        extractAllPodLabels      = true
        extractAllPodAnnotations = true
      }
      kubeletMetrics = {
        # enables the kubeletstatsreceiver and adds it to the metrics pipelines
        enabled = true
      }
    }
    # https://github.com/open-telemetry/opentelemetry-helm-charts/blob/main/charts/opentelemetry-kube-stack/daemon_scrape_configs.yaml
    # scrape_configs_file = "daemon_scrape_configs.yaml"
    config = {
      receivers = {
        kubeletstats = {
          insecure_skip_verify = true
          collection_interval  = "30s"
          metric_groups        = ["node", "pod"]
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
      }
      processors = {}
      exporters = {
        "otlp/k8s-logs" = merge(local.backends.otlp_honeycomb, {
          headers = merge(local.backends.otlp_honeycomb.headers, {
            x-honeycomb-dataset = "k8s-logs"
          })
        })
      }
      service = {
        pipelines = {
          logs = {
            receivers = [
              "filelog",
              "otlp",
            ]
            processors = [
              "memory_limiter",
              "filter",
              "logdedup",
              "probabilistic_sampler/logs",
              "k8sattributes",
              "resourcedetection/env",
              "batch",
            ]
            exporters = [
              "debug",
              "otlp/k8s-logs",
            ]
          }
          metrics = {
            receivers = [
              # "hostmetrics",
              # "kubeletstats",
              # "prometheus",
              "otlp",
            ]
            processors = [
              "memory_limiter",
              "filter",
              "k8sattributes",
              "resourcedetection/env",
              "batch",
            ]
            exporters = [
              "debug",
              # "otlp/k8s-metrics",
            ]
          }
          traces = {
            receivers = [
              "otlp",
            ]
            processors = [
              "memory_limiter",
              "filter",
              "probabilistic_sampler",
              "k8sattributes",
              "resourcedetection/env",
              "batch",
            ]
            exporters = [
              "debug",
              "otlp",
            ]
          }
        }
      }
    }
  }

  collectors = {
    cluster = local.deployment_collector
    daemon  = local.daemonset_collector
  }
}
