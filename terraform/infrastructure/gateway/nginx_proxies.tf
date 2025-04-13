# TODO: https://github.com/nginx/nginx-gateway-fabric/blob/433eba254a328935c9064bd8cbf05d5c457773ce/docs/proposals/rewrite-client-ip.md
# https://docs.nginx.com/nginx-gateway-fabric/reference/api/#gateway.nginx.org%2fv1alpha1.NginxProxy
# https://github.com/nginx/nginx-gateway-fabric/blob/433eba254a328935c9064bd8cbf05d5c457773ce/deploy/crds.yaml#L650
# resource "kubernetes_manifest" "gateway_config_proxy_protocol" {
#   manifest = {
#     apiVersion = "gateway.nginx.org/v1alpha1"
#     kind       = "NginxProxy"
#     metadata = {
#       name      = "${helm_release.gateway.metadata[0].name}-proxy-protocol"
#       namespace = local.namespace
#     }
#     spec = {
#       rewriteClientIP = {
#         mode             = "ProxyProtocol"
#         setIPRecursively = true
#         trustedAddresses = []
#       }
#     }
#   }
# }
