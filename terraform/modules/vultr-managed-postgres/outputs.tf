output "admin" {
  value = merge(local.admin, {
    url = local.admin_url
  })
  sensitive  = true
  depends_on = [kubernetes_job_v1.initdb_scripts]
}

output "app" {
  value = merge(local.app, {
    url = local.app_url
  })
  sensitive  = true
  depends_on = [kubernetes_job_v1.initdb_scripts]
}
