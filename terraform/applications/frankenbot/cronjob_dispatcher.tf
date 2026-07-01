# The dispatcher CronJob: every 30 minutes it scans enabled repos for red-CI
# Renovate PRs and spawns bounded triage Jobs (dispatch.py). It is the ONLY
# long-lived frankenbot workload terraform provisions; the triage worker Jobs are
# created at runtime by the dispatcher itself.
resource "kubernetes_cron_job_v1" "dispatcher" {
  metadata {
    name      = "frankenbot-dispatcher"
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    schedule = "*/30 * * * *"
    # Forbid: never overlap two dispatch runs (a slow run must finish before the
    # next fires). suspend/enabled is the kill switch alongside FRANKENBOT_ENABLED.
    concurrency_policy            = "Forbid"
    suspend                       = false
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3
    starting_deadline_seconds     = 120

    job_template {
      metadata {
        labels = local.labels
      }
      spec {
        # The dispatcher pod is a one-shot per tick.
        backoff_limit = 1

        template {
          metadata {
            labels = local.labels
          }
          spec {
            service_account_name = kubernetes_service_account.frankenbot.metadata[0].name
            restart_policy       = "OnFailure"
            node_selector        = local.node_selector

            image_pull_secrets {
              name = kubernetes_secret.cr.metadata[0].name
            }

            # REQUIRED (not preferred): the dispatcher must run on the
            # infrastructure node pool, same as the triage workers it spawns.
            affinity {
              node_affinity {
                required_during_scheduling_ignored_during_execution {
                  node_selector_term {
                    match_expressions {
                      key      = local.infra_nodepool_label_key
                      operator = "In"
                      values   = [local.infra_nodepool_label_value]
                    }
                  }
                }
              }
            }

            container {
              name  = "dispatcher"
              image = local.image
              args  = ["dispatch"]

              # config first, then the ESO-managed secrets. FRANKENBOT_IMAGE is
              # supplied by frankenbot-config (authoritative), so no explicit env
              # duplication is needed here.
              env_from {
                config_map_ref {
                  name = kubernetes_config_map.config.metadata[0].name
                }
              }
              env_from {
                secret_ref {
                  name = "frankenbot-github-app"
                }
              }
              env_from {
                secret_ref {
                  name = "frankenbot-anthropic"
                }
              }
              # DATABASE_URL (frankenbot app role) for cross-run dedup + the daily
              # budget gate. ONLY the dispatcher gets this; triage workers do not.
              env_from {
                secret_ref {
                  name = kubernetes_secret.db.metadata[0].name
                }
              }

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                # NO cpu limit on purpose (bursty CLI workload; a CPU limit would
                # trigger CFS throttling). Memory is bounded.
                limits = {
                  memory = "512Mi"
                }
              }

              volume_mount {
                name       = "repos"
                mount_path = "/etc/frankenbot"
                read_only  = true
              }
            }

            volume {
              name = "repos"
              config_map {
                name = kubernetes_config_map.repos.metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}
