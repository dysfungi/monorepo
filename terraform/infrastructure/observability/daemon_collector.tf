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
          collection_interval  = "30s"
          metric_groups        = ["node", "pod", "container"]
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
              "resourcedetection",
              "logdedup",
              "probabilistic_sampler/logs",
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
              "resourcedetection",
              "batch",
            ]
            exporters = [
              "debug",
              "otlphttp/grafana-cloud",
              # "otlp/honeycomb-k8s-metrics",
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
            ]
          }
        }
      }
    }
  }
}
