// https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container

resource "docker_image" "dbmate" {
  name     = "ghcr.io/amacneil/dbmate"
  platform = "linux/amd64"
}

resource "docker_container" "dbmate" {
  name       = "dbmate"
  image      = docker_image.dbmate.image_id
  attach     = true
  rm         = true
  stdin_open = true
  tty        = true
  wait       = true
  command = [
    "up",
    "--strict",
    "--verbose",
  ]
  env = [
    join("", [
      "DATABASE_URL=postgres://",
      "${vultr_database_user.automate_api.username}:${vultr_database_user.automate_api.password}",
      "@${data.vultr_database.pg.host}:${data.vultr_database.pg.port}",
      "/${vultr_database_db.automate_app.name}",
      "?sslmode=${local.dbsslmode}",
    ]),
    "DBMATE_WAIT=true",
  ]
  volumes {
    container_path = "/db"
    host_path      = abspath("../db")
  }
}
