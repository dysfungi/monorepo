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

resource "vultr_database_user" "frankenbot" {
  database_id = data.vultr_database.pg.id
  username    = "frankenbot"
  password    = var.frankenbot_postgres_password
}
