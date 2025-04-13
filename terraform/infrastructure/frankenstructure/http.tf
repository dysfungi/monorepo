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
