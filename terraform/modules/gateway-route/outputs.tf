output "hostnames" {
  value = local.hostnames
}

output "primary_hostname" {
  value = local.hostnames[0]
}
