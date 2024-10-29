locals {
  nodeSelector = {
    "kubernetes.io/os"        = "linux"
    "vke.vultr.com/node-pool" = "production"
  }
  probeTarget = "https://windmill.frank.sh/api/w/admins/jobs/run_wait_result/f/u/dmf/blackbox-probe"
}
