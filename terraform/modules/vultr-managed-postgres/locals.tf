locals {
  dbdriver = "postgres"
  sslmode  = var.sslmode
  dbname   = vultr_database_db.app.name
  admin = {
    dbdriver = local.dbdriver
    username = data.vultr_database.pg.user
    password = data.vultr_database.pg.password
    host     = data.vultr_database.pg.host
    port     = data.vultr_database.pg.port
    dbname   = local.dbname
    sslmode  = local.sslmode
  }
  admin_url = format(
    "%s://%s:%s@%s:%d/%s?sslmode=%s",
    local.admin.dbdriver,
    local.admin.username,
    local.admin.password,
    local.admin.host,
    local.admin.port,
    local.admin.dbname,
    local.admin.sslmode,
  )
  app = {
    dbdriver = local.dbdriver
    username = vultr_database_user.app.username
    password = vultr_database_user.app.password
    host     = data.vultr_database.pg.host
    port     = data.vultr_database.pg.port
    dbname   = local.dbname
    sslmode  = local.sslmode
  }
  app_url = format(
    "%s://%s:%s@%s:%d/%s?sslmode=%s",
    local.app.dbdriver,
    local.app.username,
    local.app.password,
    local.app.host,
    local.app.port,
    local.app.dbname,
    local.app.sslmode,
  )
}
