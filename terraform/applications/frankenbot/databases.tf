# Durable Postgres state for frankenbot, provisioned on the SHARED Vultr managed
# Postgres instance (the same instance automate uses — labeled "postgres").
# Mirrors fsharp/api/automate/terraform/databases.tf: a data source for the
# shared instance plus a dedicated logical database and least-privilege login
# role for frankenbot.
#
# NOTE (discrepancy vs automate): automate additionally provisions a
# vultr_database_connection_pool (pgbouncer). frankenbot's only DB client is the
# every-30-minutes dispatcher CronJob (a single short-lived connection per tick),
# so a transaction pooler buys nothing here — it is intentionally omitted.

data "vultr_database" "pg" {
  filter {
    name   = "label"
    values = ["postgres"]
  }
}

resource "vultr_database_db" "frankenbot" {
  database_id = data.vultr_database.pg.id
  name        = "frankenbot"
}

# The frankenbot login role's password is a machine-only credential: Tofu
# creates the user and the only consumer is the DATABASE_URL secret (secrets.tf)
# ESO hands the dispatcher. Generate it here instead of sourcing a hand-created
# 1Password item + TF_VAR.
resource "random_password" "frankenbot_db" {
  length  = 32
  special = false # alphanumeric -> safe in the DATABASE_URL and as a Vultr DB user password (no URL-encoding needed)
}

resource "vultr_database_user" "frankenbot" {
  database_id = data.vultr_database.pg.id
  username    = "frankenbot"
  password    = random_password.frankenbot_db.result
}
