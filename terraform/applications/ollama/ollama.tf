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
      "nodeAffinity" = {
        "requiredDuringSchedulingIgnoredDuringExecution" = {
          "nodeSelectorTerms" = {
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
