# Two hardened CronJobs run the musync CLI image (from frankistry), one per
# scheduled command. Both are driven from local.cronjobs so the hardening stays
# identical and only schedule/command vary. Hardening rationale:
#   - concurrency_policy Forbid + active_deadline_seconds: a run never overlaps
#     its predecessor and is force-killed if it wedges, bounding DB connections.
#   - starting_deadline_seconds: a missed schedule (controller down) is skipped
#     rather than stampeded once it recovers.
#   - backoff_limit + history limits: bounded retries, bounded pod litter.
#   - non-root securityContext (runAsNonRoot + explicit uid, no privilege
#     escalation, all caps dropped, read-only rootfs + RuntimeDefault seccomp):
#     least privilege. /tmp is a writable emptyDir for the dotnet runtime.
# Env is the merged terraform-managed Secret (DATABASE_URL) + the ESO-synced
# musync-onepassword Secret (external creds + deadman URLs).
resource "kubernetes_cron_job_v1" "musync" {
  for_each = local.cronjobs

  metadata {
    name      = "musync-${each.key}"
    namespace = local.namespace
    labels = merge(local.labels, {
      "app.kubernetes.io/instance" = "musync-${each.key}"
    })
  }

  spec {
    schedule                      = each.value.schedule
    concurrency_policy            = "Forbid"
    starting_deadline_seconds     = 300
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = merge(local.labels, {
          "app.kubernetes.io/instance" = "musync-${each.key}"
        })
      }

      spec {
        active_deadline_seconds = 600
        backoff_limit           = 2

        template {
          metadata {
            labels = merge(local.labels, {
              "app.kubernetes.io/instance" = "musync-${each.key}"
            })
          }

          spec {
            restart_policy = "Never"
            node_selector  = local.node_selector

            affinity {
              # https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
              node_affinity {
                preferred_during_scheduling_ignored_during_execution {
                  weight = 2
                  preference {
                    match_expressions {
                      key      = "vke.vultr.com/node-pool"
                      operator = "In"
                      values = [
                        "default",
                        local.namespace,
                      ]
                    }
                  }
                }
              }
            }

            security_context {
              run_as_non_root = true
              run_as_user     = local.app_uid
              fs_group        = local.app_uid
              seccomp_profile {
                type = "RuntimeDefault"
              }
            }

            image_pull_secrets {
              name = kubernetes_secret.cr.metadata[0].name
            }

            container {
              name  = "musync"
              image = local.image
              args  = [each.value.command]

              security_context {
                run_as_non_root            = true
                allow_privilege_escalation = false
                read_only_root_filesystem  = true
                capabilities {
                  drop = ["ALL"]
                }
              }

              resources {
                requests = {
                  cpu    = "50m"
                  memory = "128Mi"
                }
                limits = {
                  cpu    = "250m"
                  memory = "256Mi"
                }
              }

              env_from {
                secret_ref {
                  name     = kubernetes_secret.env.metadata[0].name
                  optional = false
                }
              }
              # Synced from 1Password by ESO (external_secret_musync.tf). envFrom
              # merges these keys 1:1, so FsConfig sees SONGKICK_ICS_URL,
              # SETLIST_FM_API_KEY, and SMTP_* alongside DATABASE_URL.
              env_from {
                secret_ref {
                  name     = "musync-onepassword"
                  optional = false
                }
              }

              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
              }
            }

            volume {
              name = "tmp"
              empty_dir {}
            }
          }
        }
      }
    }
  }

  # The ExternalSecret must reconcile (ESO creates musync-onepassword) and the
  # migrations must apply before a scheduled run references them.
  depends_on = [
    kustomization_resource.external_secret_musync,
    kubernetes_job.dbmate,
  ]
}
