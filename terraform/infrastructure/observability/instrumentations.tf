# https://github.com/open-telemetry/opentelemetry-operator/blob/main/docs/api/instrumentations.md
# https://docs.honeycomb.io/send-data/kubernetes/opentelemetry/add-automatic-instrumentation/#step-3-configure-automatic-instrumentation
locals {
  env_otel_exporter_otlp_endpoint = {
    # Required if endpoint is set to 4317.
    # Some language autoinstrumentation uses http/proto by default
    # so data must be sent to 4318 instead of 4317.
    name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
    value = "http://$(OTEL_NODE_IP):4318"
  }
  instrumentation = {
    enabled = true
    exporter = {
      endpoint = "http://$$(OTEL_NODE_IP):4317"
    }
    sampler = {
      type     = "parentbased_traceidratio"
      argument = "1"
    }

    dotnet = {
      env = [
        # Required if endpoint is set to 4317.
        # Dotnet autoinstrumentation uses http/proto by default
        # See https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/blob/888e2cd216c77d12e56b54ee91dafbc4e7452a52/docs/config.md\#otlp
        local.env_otel_exporter_otlp_endpoint,
      ]
    }

    go = {}

    java = {
      image = "ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2"
      env = [

        # Required if endpoint is set to 4317.
        # Java autoinstrumentation agent v2.0+ uses http/proto by default
        # See https://github.com/open-telemetry/opentelemetry-java-instrumentation/blob/9bbfe7fe4e3f65cb698d6d2320ac87372d5d572f/javaagent-tooling/src/main/java/io/opentelemetry/javaagent/tooling/config/OtlpProtocolPropertiesSupplier.java#L19
        local.env_otel_exporter_otlp_endpoint,
      ]
    }

    nginx = {}

    nodejs = {
      env = [
        {
          # Optional.
          # We recommend disabling fs automatic instrumentation because
          # it can be noisy and expensive during startup
          name  = "OTEL_NODE_DISABLED_INSTRUMENTATIONS"
          value = "fs"
        },
      ]
    }

    python = {
      env = [
        # Required if endpoint is set to 4317.
        # Python autoinstrumentation uses http/proto by default
        # so data must be sent to 4318 instead of 4317.
        local.env_otel_exporter_otlp_endpoint,
      ]
    }
  }
}
