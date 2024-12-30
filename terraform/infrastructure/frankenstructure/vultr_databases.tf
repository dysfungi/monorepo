resource "vultr_database" "pg" {
  # max connections: 97
  label                   = "postgres"
  tag                     = "postgres"
  plan                    = "vultr-dbaas-startup-cc-hp-amd-1-64-2"
  region                  = "lax"
  vpc_id                  = vultr_vpc.k8s.id
  database_engine         = "pg"
  database_engine_version = "16"
  cluster_time_zone       = "UTC"
  maintenance_dow         = "sunday"
  maintenance_time        = "10:00"
  /*
  trusted_ips = [
    format("%v/%v", vultr_vpc.k8s.v4_subnet, vultr_vpc.k8s.v4_subnet_mask),
    vultr_kubernetes.k8s.service_subnet,
    vultr_kubernetes.k8s.cluster_subnet,
    format("%v/32", var.home_ip),
  ]
  */
}
