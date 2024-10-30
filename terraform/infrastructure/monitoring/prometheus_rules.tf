resource "kubernetes_manifest" "alerts" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "PrometheusRule"
    "metadata" = {
      "name"      = "alerts"
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "groups" = [
        {
          "name" = "HTTP"
          "rules" = [
            {
              "alert" = "BlackboxProbeHttpFailure"
              "expr"  = "probe_http_status_code <= 199 OR probe_http_status_code >= 400"
              "for"   = "10m"
              "labels" = {
                "severity" = "critical"
                "type"     = "http"
              }
              "annotations" = {
                "summary" = "HTTP failure (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "HTTP status code is not 200-399",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
              }
            },
            {
              "alert" = "BlackboxProbeSlowHttp"
              "expr"  = "avg_over_time(probe_http_duration_seconds[1m]) > 1"
              "for"   = "1m"
              "labels" = {
                "severity" = "warning"
                "type"     = "http"
              }
              "annotations" = {
                "summary" = "Slow HTTP (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "HTTP request took more than 1s",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
              }
            }
          ]
        },
        {
          "name" = "SSL"
          "rules" = [
            {
              # https://samber.github.io/awesome-prometheus-alerts/rules#rule-blackbox-1-4
              "alert" = "BlackboxProbeSslCertificateWillExpireSoon"
              "expr"  = "round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 7"
              "for"   = "10m"
              "labels" = {
                "severity" = "warning"
                "type"     = "ssl"
              }
              "annotations" = {
                "summary" = "SSL certificate will expire soon (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "SSL certificate expires in less than 1 week",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
              }
            },
            {
              # https://samber.github.io/awesome-prometheus-alerts/rules#rule-blackbox-1-6
              "alert" = "BlackboxProbeSslCertificateWillExpireSoon"
              "expr"  = "round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 2"
              "for"   = "10m"
              "labels" = {
                "severity" = "critical"
                "type"     = "ssl"
              }
              "annotations" = {
                "summary" = "SSL certificate will expire soon (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "SSL certificate expires in less than 2 days",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
              }
            },
            {
              # https://samber.github.io/awesome-prometheus-alerts/rules#rule-blackbox-1-7
              "alert" = "BlackboxProbeSslCertificateExpired"
              "expr"  = "round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 0"
              "for"   = "10m"
              "labels" = {
                "severity" = "critical"
                "type"     = "ssl"
              }
              "annotations" = {
                "summary" = "SSL certificate expired (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "SSL certificate has expired already",
                  local.subannotation_value,
                  local.subannotation_labels,
                ])
              }
            },
          ]
        },
      ]
    }
  }
}
