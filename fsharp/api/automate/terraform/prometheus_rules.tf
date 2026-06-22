resource "kubernetes_manifest" "alerts" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "PrometheusRule"
    "metadata" = {
      "name"      = "alerts"
      "namespace" = kubernetes_namespace.automate.metadata[0].name
    }
    "spec" = {
      "groups" = [
        {
          "name" = "Dotnet"
          "rules" = [
            {
              "alert" = "DotnetExceptions"
              "expr"  = "systemruntime_exception_count > 0"
              "for"   = "1m"
              "labels" = {
                "severity" = "critical"
                "type"     = "dotnet"
              }
              "annotations" = {
                "summary" = "Dotnet runtime exceptions (instance {{ $labels.instance }})"
                "description" = join("\n", [
                  "Dotnet runtime is experiencing exception(s)",
                  "  VALUE = {{ $value }}",
                  "  LABEL = {{ $labels }}",
                ])
              }
            },
          ]
        },
      ]
    }
  }
}
