locals {
  autoscaling = {
    "enabled"                        = false
    "maxReplicas"                    = 4
    "targetCPUUtilizationPercentage" = 80
  }
  affinity = {
    # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
    nodeAffinity = {
      preferredDuringSchedulingIgnoredDuringExecution = [
        {
          weight = 2
          preference = {
            matchExpressions = [
              {
                key      = "vke.vultr.com/node-pool"
                operator = "In"
                values = [
                  "default",
                ]
              },
            ]
          }
        },
      ]
    }
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
