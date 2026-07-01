locals {
  namespace = one(kubernetes_namespace.musync.metadata).name
  labels = {
    "app.kubernetes.io/name"     = "musync"
    "app.kubernetes.io/instance" = "musync-cli"
  }
  node_selector = {
    "kubernetes.io/os" = "linux"
  }
  # The final image runs as the dotnet non-root user (USER $APP_UID in the
  # Dockerfile); APP_UID is 1654 on the dotnet 9 alpine images. Pinning it here
  # lets the pod securityContext enforce runAsNonRoot with an explicit uid.
  app_uid = 1654
  image = format(
    "%s/musync/cli:%s",
    data.vultr_container_registry.frankistry.urn,
    var.app_version,
  )
  # The two scheduled commands. Both share identical hardening (see cronjobs.tf);
  # only the schedule and the Argu subcommand (passed as the container arg to the
  # ./Musync ENTRYPOINT) differ. poll-songkick ingests "Going" shows every 3h;
  # curate-preshow computes probable setlists + nudges once daily at 08:00 UTC.
  cronjobs = {
    poll-songkick = {
      schedule = "0 */3 * * *"
      command  = "poll-songkick"
    }
    curate-preshow = {
      schedule = "0 8 * * *"
      command  = "curate-preshow"
    }
  }
}
