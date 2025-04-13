# https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/
resource "helm_release" "gateway" {
  name          = "nginx-gateway"
  repository    = "oci://ghcr.io/nginx/charts"
  chart         = "nginx-gateway-fabric"
  version       = local.ngf_chart_version
  namespace     = local.namespace
  wait          = true
  wait_for_jobs = true

  depends_on = [
    kustomization_resource.gateway_api_crds_p2,
    kustomization_resource.nginx_gateway_crds_p2,
  ]

  values = [
    yamlencode({
      fullnameOverride              = "nginx-gateway"
      affinity                      = local.affinity
      terminationGracePeriodSeconds = 50
      # https://github.com/nginx/nginx-gateway-fabric/blob/main/charts/nginx-gateway-fabric/values.yaml
      # https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/#configure-delayed-pod-termination-for-zero-downtime-upgrades
      nginxGateway = {
        replicaCount = 2
        resources = {
          requests = {
            cpu    = "30m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
        lifecycle = {
          preStop = {
            exec = {
              command = ["/usr/bin/gateway", "sleep", "--duration=30s"]
            }
          }
        }
        securityContext = {
          allowPrivilegeEscalation = true
        }
        snippetsFilters = {
          # https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/snippets/
          enable = true
        }
      }
      nginx = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "512Mi"
          }
        }
        lifecycle = {
          preStop = {
            exec = {
              command = ["/bin/sh", "-c", "/bin/sleep 30"]
            }
          }
        }
      }
      service = {
        # https://docs.vultr.com/vultr-kubernetes-engine#vke-load-balancer
        # https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service#example-usage
        # https://github.com/vultr/vultr-cloud-controller-manager/blob/master/docs/load-balancers.md#annotations
        annotations = {
          # https://github.com/kubernetes-sigs/external-dns/blob/master/docs/annotations/annotations.md#external-dnsalphakubernetesiohostname
          # "external-dns.alpha.kubernetes.io/hostname" = "frank.sh,*.frank.sh"
          # https://docs.vultr.com/how-to-use-a-vultr-load-balancer-with-vke#7.-using-proxy-protocol
          "service.beta.kubernetes.io/vultr-loadbalancer-proxy-protocol" = "false"
        }
      }
    }),
  ]
}

# https://cert-manager.io/docs/installation/helm/
# https://artifacthub.io/packages/helm/cert-manager/cert-manager
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.1"
  namespace  = local.namespace

  values = [
    yamlencode({
      affinity = local.affinity
      crds = {
        enabled = true
        keep    = true
      }
      resources = {
        requests = {
          cpu    = "5m"
          memory = "32Mi"
        }
        limits = {
          cpu    = "10m"
          memory = "64Mi"
        }
      }
      cainjector = {
        enabled  = true
        affinity = local.affinity
        resources = {
          requests = {
            cpu    = "5m"
            memory = "32Mi"
          }
          limits = {
            cpu    = "10m"
            memory = "64Mi"
          }
        }
      }
      startupapicheck = {
        enabled  = true
        affinity = local.affinity
        resources = {
          requests = {
            cpu    = "5m"
            memory = "32Mi"
          }
          limits = {
            cpu    = "10m"
            memory = "64Mi"
          }
        }
      }
      webhook = {
        enabled  = true
        affinity = local.affinity
        resources = {
          requests = {
            cpu    = "5m"
            memory = "16Mi"
          }
          limits = {
            cpu    = "10m"
            memory = "32Mi"
          }
        }
      }
      # https://cert-manager.io/docs/configuration/acme/dns01/#setting-nameservers-for-dns01-self-check
      extraArgs = [
        # Since Terraform Utilizes HCL as well as Helm using the Helm Template Language,
        # it's necessary to escape the `{}`, `[]`, `.`, and `,` characters twice in order
        # for it to be parsed.
        # https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release#example-usage---chart-repository-configured-outside-of-terraform
        "--dns01-recursive-nameservers-only",
        "--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53",
        # https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/integrating-cert-manager/#deploy-cert-manager
        "--feature-gates=ExperimentalGatewayAPISupport=true",
      ]
      prometheus = {
        servicemonitor = {
          enabled = true
        }
      }
    }),
  ]
}

# https://github.com/ecaramba/external-dns/blob/7a52f01ac9ff8dd2d4bb67ec851e5752507e506d/docs/tutorials/vultr.md
# https://artifacthub.io/packages/helm/external-dns/external-dns
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.16.1"
  namespace  = local.namespace

  values = [
    yamlencode({
      namespaced = false
      provider   = "cloudflare" # NOTE: only "webhook" supports more config like resources
      affinity   = local.affinity
      resources = {
        requests = {
          cpu    = "5m"
          memory = "32Mi"
        }
        limits = {
          cpu    = "10m"
          memory = "64Mi"
        }
      }
      rbac = {
        create = true
      }
      sources = [
        "gateway-grpcroute",
        "gateway-httproute",
        # "gateway-tcproute",
        # "gateway-tlsroute",
        # "gateway-udproute",
        # "ingress",
        "service",
      ]
      env = [
        {
          name = "CF_API_TOKEN"
          valueFrom = {
            secretKeyRef = {
              key      = "apiToken"
              name     = kubernetes_secret.cloudflare.metadata[0].name
              optional = false
            }
          }
        }
      ]
      serviceMonitor = {
        enabled = true
      }
    })
  ]
}
