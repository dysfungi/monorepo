data "vultr_database" "pg" {
  filter {
    name   = "label"
    values = ["postgres"]
  }
}

resource "vultr_database_db" "automate_app" {
  database_id = data.vultr_database.pg.id
  name        = "automate_app"
}

resource "vultr_database_user" "automate_api" {
  database_id = data.vultr_database.pg.id
  username    = "automate_api"
  password    = var.automate_postgres_password
}

# https://docs.vultr.com/postgresql-managed-database-guide#connection-pools-tab
resource "vultr_database_connection_pool" "automate_api" {
  database_id = data.vultr_database.pg.id
  name        = vultr_database_user.automate_api.username
  database    = vultr_database_db.automate_app.name
  username    = vultr_database_user.automate_api.username
  mode        = "transaction"
  size        = "30"
}
