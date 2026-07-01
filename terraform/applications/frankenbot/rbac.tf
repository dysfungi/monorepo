# The dispatcher runs as this ServiceAccount (dispatch.py hardcodes the
# "frankenbot" SA name on both the CronJob pod and the worker Jobs it creates).
resource "kubernetes_service_account" "frankenbot" {
  metadata {
    name      = "frankenbot"
    namespace = local.namespace
    labels    = local.labels
  }

  # Attach the Vultr CR pull secret at the SA level so EVERY pod running as this
  # SA can pull the private agent image — including the triage worker Jobs the
  # dispatcher creates in code (dispatch.py), whose pod specs do NOT set
  # image_pull_secrets. Without this they hit ImagePullBackOff. (The dispatcher
  # CronJob pod also sets it explicitly at the pod level; belt-and-suspenders.)
  image_pull_secret {
    name = kubernetes_secret.cr.metadata[0].name
  }
}

# Namespaced Role (NOT a ClusterRole): the dispatcher only ever manages triage
# Jobs and reads their pods/logs within its own namespace.
resource "kubernetes_role" "frankenbot" {
  metadata {
    name      = "frankenbot"
    namespace = local.namespace
    labels    = local.labels
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["create", "get", "list", "watch", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding" "frankenbot" {
  metadata {
    name      = "frankenbot"
    namespace = local.namespace
    labels    = local.labels
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.frankenbot.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.frankenbot.metadata[0].name
    namespace = local.namespace
  }
}
