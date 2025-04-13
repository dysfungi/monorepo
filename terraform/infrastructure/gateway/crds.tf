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
