# https://artifacthub.io/packages/helm/ollama-helm/ollama
resource "helm_release" "ollama" {
  name       = "ollama"
  repository = "https://otwld.github.io/ollama-helm"
  chart      = "ollama"
  version    = "1.12.0"
  namespace  = kubernetes_namespace.ollama.metadata[0].name

  values = [
    yamlencode({
      "replicaCount"     = 0
      "fullnameOverride" = ""
      "ollama" = {
        "gpu" = {
          "enabled" = false
          "type"    = "nvidia"
          "number"  = 1
        }
        "models" = {
          # https://ollama.com/models
          # https://github.com/ollama/ollama?tab=readme-ov-file#model-library
          # https://github.com/eugeneyan/open-llms
          "create" = []
          "pull" = [
            "deepseek-r1:1.5b",
            "deepseek-r1:8b",
            "gemma3:4b",
            "llama3.2:3b",
          ]
          "run" = [
            "deepseek-r1:1.5b",
          ]
        }
      }
      "autoscaling" = {
        "enabled"                           = false
        "minReplicas"                       = 1
        "maxReplicas"                       = 2
        "targetCPUUtilizationPercentage"    = 80
        "targetMemoryUtilizationPercentage" = 80
      }
      # Hard-gate ollama onto a GPU node pool. Nested under `affinity` because the
      # otwld/ollama-helm chart only reads `.Values.affinity`; a top-level
      # `nodeAffinity` key is silently dropped and never reaches the k8s API.
      # Inert today (replicaCount=0, gpu.enabled=false); when the GPU node pool is
      # provisioned, add its exact `vke.vultr.com/node-pool` label to `values`.
      "affinity" = {
        "nodeAffinity" = {
          "requiredDuringSchedulingIgnoredDuringExecution" = {
            "nodeSelectorTerms" = [
              {
                "matchExpressions" = [
                  {
                    "key"      = "vke.vultr.com/node-pool"
                    "operator" = "In"
                    "values" = [
                      "gpu",
                      "llm",
                      kubernetes_namespace.ollama.metadata[0].name,
                    ]
                  },
                ]
              },
            ]
          }
        }
      }
      "resources" = {
        "requests" = {
          "cpu"    = "500m"
          "memory" = "1.7Gi"
        }
        # "limits" = {
        #   "cpu"    = "800m"
        #   "memory" = "4.4Gi"
        # }
      }
      "persistentVolume" = {
        "enabled"      = true
        "size"         = "30Gi"
        "storageClass" = ""
        "volumeMode"   = ""
      }
    }),
  ]
}
