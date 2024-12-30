data "http" "github_api_meta" {
  url = "https://api.github.com/meta"

  request_headers = {
    Accept = "application/json"
  }

  retry {
    attempts     = 2
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "http" "myip" {
  url = "https://ipinfo.io/json"

  request_headers = {
    Accept = "application/json"
  }

  retry {
    attempts     = 2
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

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
  trusted_ips = concat(
    [
      format("%v/%v", vultr_vpc.k8s.v4_subnet, vultr_vpc.k8s.v4_subnet_mask),
      vultr_kubernetes.k8s.service_subnet,
      vultr_kubernetes.k8s.cluster_subnet,
      format("%v/32", var.home_ip),
    ],
    [
      for cidr in jsondecode(data.http.github_api_meta.response_body).actions
      : cidr if(
        slice(split(".", cidr), 0, 2)
        == slice(split(".", jsondecode(data.http.myip.response_body).ip), 0, 2)
      )
    ],
  )
}
