resource "vultr_object_storage" "frankenstorage" {
  cluster_id = 5
  label      = "frankenstorage"
}
