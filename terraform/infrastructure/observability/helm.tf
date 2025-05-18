# https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-kube-stack
resource "helm_release" "opentelemetry_kube_stack" {
  name             = "opentelemetry-kube-stack"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-kube-stack"
  version          = "0.5.3"
  namespace        = local.namespace
  create_namespace = false

  # https://docs.honeycomb.io/send-data/kubernetes/opentelemetry/create-telemetry-pipeline/
  values = [
    yamlencode({
      clusterName = "frank8s"
      defaultCRConfig = {
        affinity = local.affinity
      }
      collectors = {
        # https://docs.honeycomb.io/send-data/kubernetes/values-files/values-deployment.yaml
        cluster = {
          replicas = 2
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
              "transform/events" = {
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

                      # Transform the type attribtes into OpenTelemetry Severity types.
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
              "otlp/k8s-events" = {
                endpoint = "api.honeycomb.io:443"
                headers = {
                  x-honeycomb-team    = "$${env:HONEYCOMB_API_KEY}"
                  x-honeycomb-dataset = "k8s-events"
                }
              }
              "otlp/k8s-metrics" = {
                endpoint = "api.honeycomb.io:443"
                headers = {
                  x-honeycomb-team    = "$${env:HONEYCOMB_API_KEY}"
                  x-honeycomb-dataset = "k8s-metrics"
                }
              }
            }
            service = {
              pipelines = {
                logs = {
                  # receivers = ["k8sobjects"]
                  processers = ["memory_limiter", "transform/events", "resourcedetection/env", "batch"]
                  exporters  = ["debug", "otlp/k8s-events"]
                }
                metrics = {
                  # receivers = ["k8s_cluster"]
                  # processers = ["resourcedetection/env", "batch"]
                  exporters = ["debug", "otlp/k8s-metrics"]
                }
                traces = null
              }
            }
          }
        }
        # https://docs.honeycomb.io/send-data/kubernetes/values-files/values-daemonset.yaml
        daemon = {
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
            }
            processers = {
              batch                   = {}
              "resourcedetection/env" = {}
            }
            exporters = {
              otlp = {
                endpoint = "api.honeycomb.io:443"
                headers = {
                  x-honeycomb-team = "$${env:HONEYCOMB_API_KEY}"
                }
              }
              "otlp/k8s-metrics" = {
                endpoint = "api.honeycomb.io:443"
                headers = {
                  x-honeycomb-team    = "$${env:HONEYCOMB_API_KEY}"
                  x-honeycomb-dataset = "k8s-metrics"
                }
              }
              "otlp/k8s-logs" = {
                endpoint = "api.honeycomb.io:443"
                headers = {
                  x-honeycomb-team    = "$${env:HONEYCOMB_API_KEY}"
                  x-honeycomb-dataset = "k8s-logs"
                }
              }
            }
            service = {
              pipelines = {
                logs = {
                  receivers = ["otlp"]
                  # processers = ["resourcedetection/env", "batch"]
                  exporters = ["debug", "otlp/k8s-logs"]
                }
                metrics = {
                  receivers = ["otlp"]
                  # processers = ["resourcedetection/env", "batch"]
                  exporters = ["debug", "otlp/k8s-metrics"]
                }
                traces = {
                  receivers = ["otlp"]
                  # processers = ["resourcedetection/env", "batch"]
                  exporters = ["debug", "otlp"]
                }
              }
            }
          }
        }
      }
      instrumentation = local.instrumentation
      extraEnvs = [
        {
          name = "HONEYCOMB_API_KEY"
          valueFrom = {
            secretKeyRef = {
              name     = "honeycomb"
              key      = "api-key"
              optional = false
            }
          }
        },
      ]
    }),
  ]
}
