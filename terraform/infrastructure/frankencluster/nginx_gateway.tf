locals {
  foundationNodeSelector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "foundation"
  }
}

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs/data-sources/build#example-usage
data "kustomization_build" "gateway_crds" {
  path = "https://github.com/nginxinc/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v1.4.0"
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

resource "kubernetes_namespace" "gateway" {
  metadata {
    name = "nginx-gateway"
  }
}

# https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/
resource "helm_release" "gateway" {
  name          = "nginx-gateway"
  repository    = "oci://ghcr.io/nginxinc/charts"
  chart         = "nginx-gateway-fabric"
  version       = "1.4.0"
  namespace     = kubernetes_namespace.gateway.metadata[0].name
  wait          = false
  wait_for_jobs = true

  set {
    name  = "fullnameOverride"
    value = "nginx-gateway"
  }

  set {
    name  = "nginxGateway.securityContext.allowPrivilegeEscalation"
    value = true
  }

  # https://github.com/nginxinc/nginx-gateway-fabric/blob/main/charts/nginx-gateway-fabric/values.yaml
  # https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/#configure-delayed-pod-termination-for-zero-downtime-upgrades
  set_list {
    name  = "nginxGateway.lifecycle.preStop.exec.command"
    value = ["/usr/bin/gateway", "sleep", "--duration=30s"]
  }

  set_list {
    name  = "nginx.lifecycle.preStop.exec.command"
    value = ["/bin/sh", "-c", "/bin/sleep 30"]
  }

  set {
    name  = "terminationGracePeriodSeconds"
    value = "50"
    type  = "auto"
  }

  values = [
    yamlencode({
      "nodeSelector" = local.foundationNodeSelector
      "service" = {
        # https://docs.vultr.com/vultr-kubernetes-engine#vke-load-balancer
        # https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service#example-usage
        # https://github.com/vultr/vultr-cloud-controller-manager/blob/master/docs/load-balancers.md#annotations
        "annotations" = {
          # https://github.com/kubernetes-sigs/external-dns/blob/master/docs/annotations/annotations.md#external-dnsalphakubernetesiohostname
          "external-dns.alpha.kubernetes.io/hostname" = "frank.sh,*.frank.sh"
          # https://docs.vultr.com/how-to-use-a-vultr-load-balancer-with-vke#7.-using-proxy-protocol
          "service.beta.kubernetes.io/vultr-loadbalancer-proxy-protocol" = "false"
        }
      }
    }),
  ]

  depends_on = [
    kustomization_resource.gateway_crds_p2,
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

/* TODO: https://github.com/nginxinc/nginx-gateway-fabric/issues/1443
resource "kubernetes_manifest" "stage_gateway" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "Gateway"
    "metadata" = {
      "name" : "stage-web"
      "namespace" : helm_release.gateway.namespace
    }
    "spec" = {
      "gatewayClassName" = "nginx"
      "listeners" = [
        {
          "name"     = "http"
          "hostname" = "stage.api.frank.sh"
          "port"     = 80
          "protocol" = "HTTP"
          "allowedRoutes" = {
            "namespaces" = {
              "from" = "Selector"
              "selector" = {
                "matchLabels" = {
                  "tier" = "stage"
                }
              }
            }
          }
        }
      ]
    }
  }
}
*/

resource "kubernetes_manifest" "prod_gateway" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind"       = "Gateway"
    "metadata" = {
      "name" : "prod-web"
      "namespace" : helm_release.gateway.namespace
      "annotations" = {
        "cert-manager.io/cluster-issuer" = kubernetes_manifest.clusterissuer_letsencrypt_prod.manifest.metadata.name
      }
    }
    "spec" = {
      "gatewayClassName" = "nginx"
      "listeners" = [
        {
          "name"     = "http-frank.sh"
          "hostname" = "frank.sh"
          "port"     = 80
          "protocol" = "HTTP"
          "allowedRoutes" = {
            "namespaces" = {
              # TODO: filter for tier=prod
              "from" = "All"
            }
          }
        },
        {
          "name"     = "https-frank.sh"
          "hostname" = "frank.sh"
          "port"     = 443
          "protocol" = "HTTPS"
          "tls" = {
            "mode" = "Terminate"
            "certificateRefs" = [
              {
                "kind"      = "Secret"
                "name"      = kubernetes_manifest.certificate_wildcard_frank_sh.manifest.spec.secretName
                "namespace" = kubernetes_namespace.certificate.metadata[0].name
              }
            ]
          }
          "allowedRoutes" = {
            "namespaces" = {
              # TODO: filter for tier=prod
              "from" = "All"
            }
          }
        },
        {
          "name"     = "http-wildcard.frank.sh"
          "hostname" = "*.frank.sh"
          "port"     = 80
          "protocol" = "HTTP"
          "allowedRoutes" = {
            "namespaces" = {
              # TODO: filter for tier=prod
              "from" = "All"
            }
          }
        },
        {
          "name"     = "https-wildcard.frank.sh"
          "hostname" = "*.frank.sh"
          "port"     = 443
          "protocol" = "HTTPS"
          "tls" = {
            "mode" = "Terminate"
            "certificateRefs" = [
              {
                "kind"      = "Secret"
                "name"      = kubernetes_manifest.certificate_wildcard_frank_sh.manifest.spec.secretName
                "namespace" = kubernetes_namespace.certificate.metadata[0].name
              }
            ]
          }
          "allowedRoutes" = {
            "namespaces" = {
              # TODO: filter for tier=prod
              "from" = "All"
            }
          }
        }
      ]
    }
  }
}

# https://docs.nginx.com/nginx-gateway-fabric/how-to/monitoring/prometheus/#available-metrics-in-nginx-gateway-fabric
# https://github.com/nginxinc/nginx-prometheus-exporter#exported-metrics
resource "kubernetes_manifest" "gateway_pod_monitor" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "PodMonitor"
    "metadata" = {
      "name"      = helm_release.gateway.name
      "namespace" = helm_release.gateway.namespace
    }
    "spec" = {
      "podTargetLabels" = [
        "app.kubernetes.io/instance",
        "app.kubernetes.io/name",
        "pod-template-hash"
      ]
      "podMetricsEndpoints" = [
        {
          "port" = "metrics"
        },
      ]
      "namespaceSelector" = {
        "any" = false
        "matchNames" = [
          helm_release.gateway.namespace,
        ]
      }
      "selector" = {
        "matchLabels" = {
          "app.kubernetes.io/instance" = helm_release.gateway.name,
          "app.kubernetes.io/name"     = "nginx-gateway-fabric"
        }
      }
    }
  }
}
