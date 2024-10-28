data "vultr_database" "pg" {
  filter {
    name   = "label"
    values = ["postgres"]
  }
}

resource "vultr_database_db" "windmill_app" {
  database_id = data.vultr_database.pg.id
  name        = "windmill_app"
}

resource "vultr_database_user" "windmill_app" {
  database_id = data.vultr_database.pg.id
  username    = "windmill_app"
  password    = var.windmill_postgres_password
}

# https://docs.vultr.com/postgresql-managed-database-guide#connection-pools-tab
resource "vultr_database_connection_pool" "windmill_app" {
  database_id = data.vultr_database.pg.id
  name        = "windmill_app"
  database    = vultr_database_db.windmill_app.name
  username    = vultr_database_user.windmill_app.username
  mode        = "transaction"
  size        = "30"
}
