locals {
  github_cidrs = [
    for cidr in jsondecode(data.http.github_api_meta.response_body).actions : cidr
    if !strcontains(cidr, "::")
  ]
  myip       = jsondecode(data.http.myip.response_body).ip
  myip_parts = split(".", local.myip)
  db_plans = {
    # https://www.vultr.com/pricing/#managed-databases
    cloud_compute = {
      postgresql_36usd = "vultr-dbaas-startup-cc-hp-amd-1-64-2"
    }
  }
}

resource "vultr_database" "pg" {
  # max connections: 97
  label                   = "postgres"
  tag                     = "postgres"
  plan                    = local.db_plans.cloud_compute.postgresql_36usd
  region                  = "lax"
  vpc_id                  = vultr_vpc.k8s.id
  database_engine         = "pg"
  database_engine_version = "16"
  cluster_time_zone       = "UTC"
  maintenance_dow         = "sunday"
  maintenance_time        = "10:00"
  trusted_ips = concat(
    [
      format("%v/%v", vultr_vpc.k8s.v4_subnet, vultr_vpc.k8s.v4_subnet_mask),
      vultr_kubernetes.k8s.service_subnet,
      vultr_kubernetes.k8s.cluster_subnet,
      format("%v/32", var.home_ip),
    ],
    [
      for cidr_parts in [for cidr in local.github_cidrs : split(".", cidr)] : join(".", cidr_parts)
      if slice(cidr_parts, 0, min(2, length(cidr_parts))) == slice(local.myip_parts, 0, 2)
    ],
  )
}
