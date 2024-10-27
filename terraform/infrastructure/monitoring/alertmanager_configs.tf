resource "kubernetes_manifest" "notifications" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1alpha1"
    "kind"       = "AlertmanagerConfig"
    "metadata" = {
      "name"      = "notifications"
      "namespace" = helm_release.kube_prometheus.namespace
    }
    "spec" = {
      "route" = {
        "receiver" = "void"
        "groupBy" = [
          "alertname",
        ]
        "groupWait"      = "30s"
        "groupInterval"  = "5m"
        "repeatInterval" = "12h"
        "routes" = [
          {
            "receiver"       = "deadmans-switch"
            "groupWait"      = "0s"
            "groupInterval"  = "30s"
            "repeatInterval" = "30s"
            "matchers" = [
              {
                "name"      = "severity"
                "matchType" = "="
                "value"     = "heartbeat"
              },
            ]
          },
          {
            "receiver" = "high-priority"
            "matchers" = [
              {
                "name"      = "severity"
                "matchType" = "=~"
                "value"     = "error|critical"
              },
            ]
          },
          {
            "receiver" = "low-priority"
            "matchers" = [
              {
                "name"      = "severity"
                "matchType" = "="
                "value"     = "warning"
              },
            ]
          },
        ]
      }
      "receivers" = [
        {
          "name" = "deadmans-switch"
          "webhookConfigs" = [
            {
              "sendResolved" = false
              "urlSecret" = {
                "key"      = "healthchecksioPingUrl"
                "name"     = kubernetes_secret.prom_secrets.metadata[0].name
                "optional" = false
              }
            },
          ]
        },
        {
          "name" = "high-priority"
          "discordConfigs" = [
            {
              "sendResolved" = true
              "apiURL" = {
                "key"      = "discordWebhookAlerts"
                "name"     = kubernetes_secret.prom_secrets.metadata[0].name
                "optional" = false
              }
            },
          ]
          "emailConfigs" = [
            # https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1alpha1.EmailConfig
            {
              "sendResolved" = true
              "to"           = "alerts@frank.sh"
            },
          ]
        },
        {
          "name" = "low-priority"
          "emailConfigs" = [
            # https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1alpha1.EmailConfig
            {
              "sendResolved" = false
              "to"           = var.todoist_email
            },
          ]
        },
        { "name" = "void" },
      ]
    }
  }
}
