resource "helm_release" "ntfy" {
  name       = "ntfy"
  repository = "https://repo.helmforge.dev"
  chart      = "ntfy"
  version    = "1.1.11"
  namespace  = local.namespace

  values = [
    yamlencode({
      # The chart's fullname defaults to "<release>-<chart>" = "ntfy-ntfy", which
      # would name the Service/PVC/ConfigMap "ntfy-ntfy" and break the HTTPRoute
      # backendRef (routes.tf references helm_release.ntfy.name = "ntfy"). Override
      # so every object is plainly "ntfy".
      fullnameOverride = "ntfy"

      ntfy = {
        # Required for correct links, attachments, and web push. Emitted as base-url.
        baseUrl = "https://ntfy.frank.sh"

        # Trust X-Forwarded-* from the NGF gateway so visitor rate limits key off the
        # real client IP rather than the gateway pod IP.
        behindProxy = true

        # PUBLIC read-write by design -- this is an open (but hardened) relay; see
        # README.md. ntfy's privacy is topic-name obscurity either way, so auth is
        # deferred. To go private: set this to "deny-all" and uncomment the auth-users
        # block in extraConfig below.
        authDefaultAccess = "read-write"

        # Hardening for a publicly reachable instance. The chart already emits
        # cache-file + auth-file under the persisted /var/cache/ntfy mount, and never
        # emits attachment-cache-dir -- so attachments stay disabled (nobody can write
        # files to the PVC). Do NOT add cache-file/auth-file/auth-default-access here:
        # the chart emits all three, so a duplicate key would break server.yml.
        extraConfig = <<-EOT
          cache-duration: "12h"
          visitor-request-limit-burst: 60
          visitor-request-limit-replenish: "10s"
          visitor-message-daily-limit: 2000
          # --- GO PRIVATE -----------------------------------------------------------
          # 1. set authDefaultAccess = "deny-all" above (do NOT add auth-default-access
          #    here -- the chart emits it from authDefaultAccess => duplicate key).
          # 2. add a hashed admin user (bcrypt from `ntfy user hash`) via ESO:
          # auth-users:
          #   - "admin:$2a$10$REPLACE_WITH_BCRYPT_HASH:admin"   # username:hash:role
          # auth-access:
          #   - "admin:*:rw"                                     # user:topic:perm
          # --------------------------------------------------------------------------
        EOT
      }

      # SQLite cache (and auth.db, when private) persist on Vultr block storage across
      # restarts. storageClass "" => cluster default (vultr-block-storage). The chart
      # hardcodes replicas=1 + Recreate strategy, so the single-writer RWO volume is
      # safe. Mount path is hardcoded to /var/cache/ntfy by the chart (not overridable).
      #
      # RESILIENCE EXCEPTION: the repo convention (see terraform/applications/README.md)
      # is that app Deployments run replicas >= 2 with topologySpreadConstraints so a
      # node loss can't take a whole service offline. ntfy is a documented exception:
      # it is a single-writer workload (SQLite on an RWO volume, no cross-instance
      # message fan-out), so it CANNOT run more than one replica. A node loss makes
      # ntfy briefly unavailable until the pod reschedules — accepted for this
      # best-effort notification relay.
      persistence = {
        enabled      = true
        size         = "2Gi"
        storageClass = ""
      }

      # Lean profile (see docs/right-sizing-resources.md): 7-day actuals show a tiny,
      # flat footprint for this single-replica relay. CPU limit already omitted.
      resources = {
        requests = {
          cpu    = "10m"
          memory = "32Mi"
        }
        limits = {
          memory = "32Mi"
        }
      }
    }),
  ]
}
