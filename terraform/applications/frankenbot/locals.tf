locals {
  name      = "frankenbot"
  namespace = one(kubernetes_namespace.frankenbot.metadata).name

  # sslmode for the Vultr managed Postgres connection URLs (databases.tf /
  # secrets.tf). Vultr managed Postgres requires TLS. Mirrors automate.
  dbsslmode = "require"

  labels = {
    "app.kubernetes.io/name"     = "frankenbot"
    "app.kubernetes.io/instance" = "frankenbot"
  }

  node_selector = {
    "kubernetes.io/os" = "linux"
  }

  # Agent image (dispatch + triage share one image); tag comes from the CI build
  # output. Matches python/pipeline/frankenbot/docker-compose.yaml.
  image = "sjc.vultrcr.com/frankistry/frankenbot/agent:${var.app_version}"

  # Vultr VKE infrastructure node pool. The dispatcher (and the triage workers it
  # spawns) are REQUIRED-scheduled here. VERIFY the live label at deploy time:
  #   kubectl get nodes --show-labels | tr ',' '\n' | grep node-pool
  # This value is also exported to the dispatcher as FRANKENBOT_INFRA_NODEPOOL_LABEL
  # (key=value) so it stamps the same selector onto the worker Jobs.
  infra_nodepool_label_key   = "vke.vultr.com/node-pool"
  infra_nodepool_label_value = "infrastructure"
}
