# https://docs.vultr.com/vultr-kubernetes-engine#vke-load-balancer
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service#example-usage

# https://github.com/vultr/cert-manager-webhook-vultr?tab=readme-ov-file#request-a-certificate
resource "kubernetes_manifest" "certificate_api_frank_sh" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "api-frank-sh"
      "namespace" = kubernetes_namespace.staging.metadata[0].name
    }
    "spec" = {
      "commonName" = "api.frank.sh"
      "dnsNames"   = ["api.frank.sh"]
      "issuerRef" = {
        "name" = "letsencrypt-prod"
        "kind" = "ClusterIssuer"
      }
      "secretName" = "api-frank-sh-tls"
    }
  }
}

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
  name          = "gateway"
  repository    = "oci://ghcr.io/nginxinc/charts"
  chart         = "nginx-gateway-fabric"
  version       = "1.4.0"
  namespace     = kubernetes_namespace.gateway.metadata[0].name
  wait          = false
  wait_for_jobs = true

  depends_on = [
    kustomization_resource.gateway_crds_p2,
  ]
}
