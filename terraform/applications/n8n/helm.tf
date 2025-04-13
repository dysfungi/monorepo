# https://artifacthub.io/packages/helm/open-8gears/n8n
# resource "helm_release" "n8n" {
#   name       = "n8n"
#   repository = "oci://8gears.container-registry.com/library"
#   chart      = "n8n"
#   version    = "0.25.2"
#   namespace  = local.namespace
#
#   values = [
#     yamlencode({
#       affinity = {
#         # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
#         nodeAffinity = {
#           preferredDuringSchedulingIgnoredDuringExecution = [
#             {
#               weight = 2
#               preference = {
#                 matchExpressions = [
#                   {
#                     key      = "vke.vultr.com/node-pool"
#                     operator = "In"
#                     values = [
#                       "default",
#                     ]
#                   },
#                 ]
#               }
#             },
#           ]
#         }
#       }
#       "generic" = {
#         "timezone" = "America/Los_Angeles"
#       }
#       "extraEnv" = {
#         "WEBHOOK_TUNNEL_URL" = "https://n8n.frank.sh/"
#       }
#     }),
#   ]
# }
