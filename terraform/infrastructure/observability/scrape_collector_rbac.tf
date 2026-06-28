# RBAC for the dedicated scrape collector (see scrape_collector.tf).
#
# The opentelemetry-operator will auto-create collector RBAC ONLY if it itself has
# permission to create ClusterRoles/ClusterRoleBindings; for the targetAllocator it
# creates a ServiceAccount with NO policy attached. Rather than depend on operator
# self-RBAC (which kube-stack 0.6.1 does not grant for prometheusCR discovery), we
# declare both ServiceAccounts and their ClusterRoles explicitly. This is always
# safe: if the operator also reconciles a role, these are additive. Two distinct
# SAs keep the discovery (target allocator) and scrape (collector) permission sets
# minimal and separated.
#
# Uses the default `kubernetes` provider, matching secrets.tf / namespaces.tf.

# --- Target allocator: discovers Prometheus Operator CRs -----------------------

resource "kubernetes_service_account" "scrape_target_allocator" {
  metadata {
    name      = "otel-scrape-targetallocator"
    namespace = local.namespace
  }
}

resource "kubernetes_cluster_role" "scrape_target_allocator" {
  metadata {
    name = "otel-scrape-targetallocator"
  }

  # Watch the Prometheus Operator monitor CRs to build the scrape target list.
  rule {
    api_groups = ["monitoring.coreos.com"]
    resources = [
      "servicemonitors",
      "podmonitors",
      "probes",
      "scrapeconfigs",
    ]
    verbs = ["get", "list", "watch"]
  }

  # Namespace lookups for namespace-scoped selectors.
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "scrape_target_allocator" {
  metadata {
    name = "otel-scrape-targetallocator"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.scrape_target_allocator.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.scrape_target_allocator.metadata[0].name
    namespace = local.namespace
  }
}

# --- Collector: prometheus receiver scraping the discovered targets ------------

resource "kubernetes_service_account" "scrape_collector" {
  metadata {
    name      = "otel-scrape-collector"
    namespace = local.namespace
  }
}

resource "kubernetes_cluster_role" "scrape_collector" {
  metadata {
    name = "otel-scrape-collector"
  }

  # Core objects the prometheus receiver needs for Kubernetes SD + scraping.
  rule {
    api_groups = [""]
    resources = [
      "nodes",
      "nodes/metrics",
      "services",
      "endpoints",
      "pods",
      "configmaps",
    ]
    verbs = ["get", "list", "watch"]
  }

  # Scraping the kubelet/api `/metrics` endpoints directly.
  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "scrape_collector" {
  metadata {
    name = "otel-scrape-collector"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.scrape_collector.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.scrape_collector.metadata[0].name
    namespace = local.namespace
  }
}
