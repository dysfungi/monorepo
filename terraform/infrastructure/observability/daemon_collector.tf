locals {
  daemon_collector = {
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
              "otlp",
            ]
            processors = [
              "memory_limiter",
              "filter",
              "k8sattributes",
              "transform",
              "resourcedetection/env",
              "logdedup",
              "probabilistic_sampler/logs",
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
              "transform",
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
              "k8sattributes",
              "transform",
              "resourcedetection/env",
              "probabilistic_sampler",
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
}
