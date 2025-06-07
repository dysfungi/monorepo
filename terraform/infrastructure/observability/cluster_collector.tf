locals {
  cluster_collector = {
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
        "otlp/honeycomb-k8s-events" = merge(local.backends.otlp_honeycomb, {
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
              "k8sattributes",
              "transform/k8s-events",
              "transform",
              "resourcedetection",
              "logdedup",
              "probabilistic_sampler/logs",
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
              "resourcedetection",
              "batch",
            ]
            exporters = [
              "debug",
              "otlphttp/grafana-cloud",
              # "otlp/honeycomb-k8s-metrics",
            ]
          }
          traces = null
        }
      }
    }
  }
}
