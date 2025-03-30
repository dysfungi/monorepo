locals {
  ngf_chart_version = "1.6.2"
}

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs/data-sources/build#example-usage
data "kustomization_build" "gateway_crds" {
  path = "https://github.com/nginxinc/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v${local.ngf_chart_version}"
}

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs/resources/resource#module-example
# https://registry.terraform.io/providers/alekc/kubectl/latest/docs
resource "kustomization_resource" "gateway_crds_p0" {
  for_each = data.kustomization_build.gateway_crds.ids_prio[0]
  manifest = data.kustomization_build.gateway_crds.manifests[each.value]
}

resource "kustomization_resource" "gateway_crds_p1" {
  for_each = data.kustomization_build.gateway_crds.ids_prio[1]
  manifest = data.kustomization_build.gateway_crds.manifests[each.value]
  depends_on = [
    kustomization_resource.gateway_crds_p0,
  ]
}

resource "kustomization_resource" "gateway_crds_p2" {
  for_each = data.kustomization_build.gateway_crds.ids_prio[2]
  manifest = data.kustomization_build.gateway_crds.manifests[each.value]
  depends_on = [
    kustomization_resource.gateway_crds_p1,
  ]
}

# https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/
resource "helm_release" "gateway" {
  name          = "nginx-gateway"
  repository    = "oci://ghcr.io/nginxinc/charts"
  chart         = "nginx-gateway-fabric"
  version       = local.ngf_chart_version
  namespace     = kubernetes_namespace.gateway.metadata[0].name
  wait          = true
  wait_for_jobs = true

  depends_on = [
    kustomization_resource.gateway_crds_p2,
  ]

  values = [
    yamlencode({
      "fullnameOverride"              = "nginx-gateway"
      "affinity"                      = local.affinity
      "terminationGracePeriodSeconds" = 50
      # https://github.com/nginxinc/nginx-gateway-fabric/blob/main/charts/nginx-gateway-fabric/values.yaml
      # https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/#configure-delayed-pod-termination-for-zero-downtime-upgrades
      "nginxGateway" = {
        "replicaCount" = 2
        "lifecycle" = {
          "preStop" = {
            "exec" = {
              "command" = ["/usr/bin/gateway", "sleep", "--duration=30s"]
            }
          }
        }
        "securityContext" = {
          "allowPrivilegeEscalation" = true
        }
      }
      "nginx" = {
        "lifecycle" = {
          "preStop" = {
            "exec" = {
              "command" = ["/bin/sh", "-c", "/bin/sleep 30"]
            }
          }
        }
      }
      "service" = {
        # https://docs.vultr.com/vultr-kubernetes-engine#vke-load-balancer
        # https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service#example-usage
        # https://github.com/vultr/vultr-cloud-controller-manager/blob/master/docs/load-balancers.md#annotations
        "annotations" = {
          # https://github.com/kubernetes-sigs/external-dns/blob/master/docs/annotations/annotations.md#external-dnsalphakubernetesiohostname
          # "external-dns.alpha.kubernetes.io/hostname" = "frank.sh,*.frank.sh"
          # https://docs.vultr.com/how-to-use-a-vultr-load-balancer-with-vke#7.-using-proxy-protocol
          "service.beta.kubernetes.io/vultr-loadbalancer-proxy-protocol" = "false"
        }
      }
    }),
  ]
}

/* TODO: https://github.com/nginxinc/nginx-gateway-fabric/blob/433eba254a328935c9064bd8cbf05d5c457773ce/docs/proposals/rewrite-client-ip.md
# https://docs.nginx.com/nginx-gateway-fabric/reference/api/#gateway.nginx.org%2fv1alpha1.NginxProxy
# https://github.com/nginxinc/nginx-gateway-fabric/blob/433eba254a328935c9064bd8cbf05d5c457773ce/deploy/crds.yaml#L650
resource "kubernetes_manifest" "gateway_config_proxy_protocol" {
  manifest = {
    "apiVersion" = "gateway.nginx.org/v1alpha1"
    "kind"       = "NginxProxy"
    "metadata" = {
      "name"      = "${helm_release.gateway.metadata[0].name}-proxy-protocol"
      "namespace" = kubernetes_namespace.gateway.metadata[0].name
    }
    "spec" = {
      "rewriteClientIP" = {
        "mode"             = "ProxyProtocol"
        "setIPRecursively" = true
        "trustedAddresses" = []
      }
    }
  }
}
*/
