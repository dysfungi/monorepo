data "vultr_database" "pg" {
  filter {
    name   = "label"
    values = ["postgres"]
  }
}

resource "vultr_database_user" "pg_exporter" {
  database_id = data.vultr_database.pg.id
  username    = "postgres_exporter"
  password    = var.exporter_postgres_password
}

resource "vultr_database_connection_pool" "pg_exporter" {
  database_id = data.vultr_database.pg.id
  name = join("-", [
    vultr_database_user.pg_exporter.username,
    data.vultr_database.pg.dbname,
  ])
  database = data.vultr_database.pg.dbname
  username = vultr_database_user.pg_exporter.username
  mode     = "transaction"
  size     = 4
}
