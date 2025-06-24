locals {
  namespace         = one(kubernetes_namespace.gateway.metadata).name
  ngf_chart_version = "2.0.1"
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
                  "infrastructure",
                  local.namespace,
                ]
              },
            ]
          }
        },
      ]
    }
  }
}
