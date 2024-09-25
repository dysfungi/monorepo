# https://docs.vultr.com/vultr-kubernetes-engine#vke-load-balancer
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service#example-usage

/*
# https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer
resource "kubernetes_service" "load_balancer" {
    metadata {
        name = "lb-https"
        annotations = {
            "service.beta.kubernetes.io/vultr-loadbalancer-protocol" = "http"
            "service.beta.kubernetes.io/vultr-loadbalancer-https-ports" ="443"
            # You will need to have created a TLS Secret and pass in the name as the value
            "service.beta.kubernetes.io/vultr-loadbalancer-ssl" = "ssl-secret" # TODO
        }
    }
    spec {
        type = "LoadBalancer"
        selector = {
            app = "shared" # TODO: apply to container tags
        }
        port {
            name = "http"
            port = 80
            target_port = 8080
        }
        port {
            name = "https"
            port = 443
            target_port = 4343
        }
    }
}
*/

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

  # https://github.com/kubernetes-sigs/external-dns/blob/master/docs/annotations/annotations.md#external-dnsalphakubernetesiohostname
  set {
    name  = "service.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname"
    value = "frank.sh\\,*.frank.sh"
  }

  /*
  set {
    name  = "service.create"
    value = false
  }
  */

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

  depends_on = [
    kustomization_resource.gateway_crds_p2,
  ]
}

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

/* TODO: customize Service LoadBalancer configuration?
resource "vultr_load_balancer" "gateway" {
  region = "lax"
  label = ""
  balancing_algorithm = "roundrobin"
  proxy_protocol = true
  ssl_redirect = false
  vpc =
}
*/
