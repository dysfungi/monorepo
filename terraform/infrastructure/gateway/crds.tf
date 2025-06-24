locals {
  gateway_api_crds = [
    "apiextensions.k8s.io/CustomResourceDefinition/_/grpcroutes.gateway.networking.k8s.io",
    "apiextensions.k8s.io/CustomResourceDefinition/_/httproutes.gateway.networking.k8s.io",
    "apiextensions.k8s.io/CustomResourceDefinition/_/gateways.gateway.networking.k8s.io",
    "apiextensions.k8s.io/CustomResourceDefinition/_/gatewayclasses.gateway.networking.k8s.io",
    "apiextensions.k8s.io/CustomResourceDefinition/_/referencegrants.gateway.networking.k8s.io",
  ]
  nginx_gateway_crds = [
    "apiextensions.k8s.io/CustomResourceDefinition/_/clientsettingspolicies.gateway.nginx.org",
    "apiextensions.k8s.io/CustomResourceDefinition/_/snippetsfilters.gateway.nginx.org",
    "apiextensions.k8s.io/CustomResourceDefinition/_/upstreamsettingspolicies.gateway.nginx.org",
    "apiextensions.k8s.io/CustomResourceDefinition/_/observabilitypolicies.gateway.nginx.org",
    "apiextensions.k8s.io/CustomResourceDefinition/_/nginxproxies.gateway.nginx.org",
  ]

}

import {
  for_each = local.gateway_api_crds
  to       = kustomization_resource.gateway_api_crds_p0[each.value]
  id       = each.value
}

import {
  for_each = local.nginx_gateway_crds
  to       = kustomization_resource.nginx_gateway_crds_p0[each.value]
  id       = each.value
}

# https://artifacthub.io/packages/helm/nginx-gateway-fabric/nginx-gateway-fabric#upgrading-the-gateway-resources
# https://registry.terraform.io/providers/kbst/kustomization/latest/docs/data-sources/build#example-usage
data "kustomization_build" "gateway_api_crds" {
  path = "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v${local.ngf_chart_version}"
}

# https://registry.terraform.io/providers/kbst/kustomization/latest/docs/resources/resource#module-example
# https://registry.terraform.io/providers/alekc/kubectl/latest/docs
resource "kustomization_resource" "gateway_api_crds_p0" {
  for_each = data.kustomization_build.gateway_api_crds.ids_prio[0]
  manifest = data.kustomization_build.gateway_api_crds.manifests[each.value]
}

resource "kustomization_resource" "gateway_api_crds_p1" {
  for_each = data.kustomization_build.gateway_api_crds.ids_prio[1]
  manifest = data.kustomization_build.gateway_api_crds.manifests[each.value]
  wait     = true
  timeouts {
    create = "2m"
    update = "2m"
  }
  depends_on = [
    kustomization_resource.gateway_api_crds_p0,
  ]
}

resource "kustomization_resource" "gateway_api_crds_p2" {
  for_each = data.kustomization_build.gateway_api_crds.ids_prio[2]
  manifest = data.kustomization_build.gateway_api_crds.manifests[each.value]
  depends_on = [
    kustomization_resource.gateway_api_crds_p1,
  ]
}

# https://artifacthub.io/packages/helm/nginx-gateway-fabric/nginx-gateway-fabric#upgrading-the-crds
data "kustomization_build" "nginx_gateway_crds" {
  path = "https://github.com/nginx/nginx-gateway-fabric/config/crd?ref=v${local.ngf_chart_version}"
}

resource "kustomization_resource" "nginx_gateway_crds_p0" {
  for_each = data.kustomization_build.nginx_gateway_crds.ids_prio[0]
  manifest = data.kustomization_build.nginx_gateway_crds.manifests[each.value]
}

resource "kustomization_resource" "nginx_gateway_crds_p1" {
  for_each = data.kustomization_build.nginx_gateway_crds.ids_prio[1]
  manifest = data.kustomization_build.nginx_gateway_crds.manifests[each.value]
  wait     = true
  timeouts {
    create = "2m"
    update = "2m"
  }
  depends_on = [
    kustomization_resource.nginx_gateway_crds_p0,
  ]
}

resource "kustomization_resource" "nginx_gateway_crds_p2" {
  for_each = data.kustomization_build.nginx_gateway_crds.ids_prio[2]
  manifest = data.kustomization_build.nginx_gateway_crds.manifests[each.value]
  depends_on = [
    kustomization_resource.nginx_gateway_crds_p1,
  ]
}
