resource "kubernetes_secret" "cr" {
  // https://docs.vultr.com/how-to-use-vultr-container-registry-with-kubernetes#generate-the-vultr-container-registry-kubernetes-credentials
  metadata {
    name      = "vultr-cr-credentials"
    namespace = local.namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.dockerconfigjson
  }
}

# App-facing environment: the single terraform-derived key the CronJobs need.
# DATABASE_URL is the app connection URL emitted by the postgres module (app
# role, transaction pool). All other runtime config is external and is synced
# from 1Password by the ESO ExternalSecret "musync-onepassword" (see
# external_secret_musync.tf); the CronJobs mount both Secrets via env_from so
# FsConfig sees one merged environment.
resource "kubernetes_secret" "env" {
  metadata {
    name      = "musync-env"
    namespace = local.namespace
  }
  data = {
    DATABASE_URL = module.postgres.app.url
  }
}

# dbmate runs migrations as the cluster admin role: migration 0001 GRANTs
# privileges to musync_api, which only a role with grant option can perform, so
# the migrator must not use the app role. ADMIN_URL targets the musync_app db.
resource "kubernetes_secret" "dbmate" {
  metadata {
    name      = "musync-dbmate"
    namespace = local.namespace
  }
  data = {
    DATABASE_URL = module.postgres.admin.url
  }
}
