locals {
  autoscaling = {
    "enabled"                        = false
    "maxReplicas"                    = 4
    "targetCPUUtilizationPercentage" = 80
  }
  nodeSelector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "default"
  }
  resources = {
    "limits" = {
      "cpu"    = "0.5"
      "memory" = "1Gi"
    }
    "requests" = {
      "cpu"    = "0.1"
      "memory" = "0.5Gi"
    }
  }
}
