data "vultr_database" "pg" {
  filter {
    name   = "label"
    values = ["postgres"]
  }
}

resource "vultr_database_db" "app" {
  database_id = data.vultr_database.pg.id
  name        = var.app_dbname
}

resource "vultr_database_user" "app" {
  database_id = data.vultr_database.pg.id
  username    = var.app_username
  password    = var.app_password
}

# https://docs.vultr.com/postgresql-managed-database-guide#connection-pools-tab
resource "vultr_database_connection_pool" "app" {
  database_id = data.vultr_database.pg.id
  name        = vultr_database_user.app.username
  database    = vultr_database_db.app.name
  username    = vultr_database_user.app.username
  mode        = var.connection_pool_mode
  size        = format("%d", var.connection_pool_size)
}
