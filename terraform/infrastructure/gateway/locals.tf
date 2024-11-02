locals {
  affinity = {
    # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
    "nodeAffinity" = {
      "preferredDuringSchedulingIgnoredDuringExecution" = [
        {
          "weight" = 2
          "preference" = {
            "matchExpressions" = [
              {
                "key"      = "vke.vultr.com/node-pool"
                "operator" = "In"
                "values" = [
                  kubernetes_namespace.gateway.metadata[0].name,
                ]
              },
            ]
          }
        },
      ]
    }
  }
}
