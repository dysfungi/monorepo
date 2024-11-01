# https://artifacthub.io/packages/helm/ollama-helm/ollama
resource "helm_release" "ollama" {
  name       = "ollama"
  repository = "https://otwld.github.io/ollama-helm"
  chart      = "ollama"
  version    = "0.63.0"
  namespace  = kubernetes_namespace.ollama.metadata[0].name

  values = [
    yamlencode({
      "replicaCount"     = 1
      "fullnameOverride" = ""
      "ollama" = {
        "gpu" = {
          "enabled" = false
          "type"    = "nvidia"
          "number"  = 1
        }
        "models" = [
          # https://github.com/ollama/ollama?tab=readme-ov-file#model-library
          # https://github.com/eugeneyan/open-llms
          # "llama2",
          # "mistral",
        ]
      }
      "autoscaling" = {
        "enabled"                           = false
        "minReplicas"                       = 1
        "maxReplicas"                       = 2
        "targetCPUUtilizationPercentage"    = 80
        "targetMemoryUtilizationPercentage" = 80
      }
      "nodeSelector" = {
        "kubernetes.io/os"        = "linux"
        "vke.vultr.com/node-pool" = "llm"
      }
      "resources" = {
        "requests" = {
          "cpu"    = "1"
          "memory" = "4Gi"
        }
        "limits" = {
          "cpu"    = "2"
          "memory" = "8Gi"
        }
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
