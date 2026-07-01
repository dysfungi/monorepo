# Non-secret runtime configuration. Injected into the dispatcher (and the triage
# Jobs it spawns) via envFrom; every key MUST match a name frankenbot/config.py
# reads from the environment.
resource "kubernetes_config_map" "config" {
  metadata {
    name      = "frankenbot-config"
    namespace = local.namespace
    labels    = local.labels
  }
  data = {
    FRANKENBOT_ENABLED              = var.enabled ? "true" : "false"
    FRANKENBOT_NAMESPACE            = local.namespace
    FRANKENBOT_MAX_CONCURRENT_JOBS  = tostring(var.max_concurrent_jobs)
    FRANKENBOT_INFRA_NODEPOOL_LABEL = "${local.infra_nodepool_label_key}=${local.infra_nodepool_label_value}"
    # The dispatcher passes this image tag onto the worker Jobs it creates.
    FRANKENBOT_IMAGE = local.image
  }
}

# Repo policy list, mounted read-only at /etc/frankenbot/repos.yaml
# (config.py REPOS_FILE_DEFAULT). Sourced from the same file the agent image
# ships, so the in-cluster policy tracks the repo.
resource "kubernetes_config_map" "repos" {
  metadata {
    name      = "frankenbot-repos"
    namespace = local.namespace
    labels    = local.labels
  }
  data = {
    "repos.yaml" = file("${path.module}/../../../python/pipeline/frankenbot/repos.yaml")
  }
}
