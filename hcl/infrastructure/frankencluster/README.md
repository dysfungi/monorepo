# frankencluster

The goal of this infrastructure project is to configure and setup the shared
Kubernetes cluster.

## Tools

### Terraform

**Providers:**

- [Kubernetes Terraform Provider][terraform-provider-k8s]
- [Helm Terraform Provider][terraform-provider-helm]

## Shared Resources

### Kubernetes Cluster (frank8s)

Owned by [frankenstructure](../frankenstructure).

**Requires:**

- Environment variable: `$VAR_TF_kubeconfig`

### Certificate Manager

**Requires:**

- Environment variable: `$VAR_TF_vultr_api_key`

**Resources:**

- [Install Cert Manager using Helm][cert-manager-helm-install]
- [Verify Cert Manager install][cert-manager-verify]
- [Vultr Webhook for Cert Manager][vultr-webhook-cert-manager]

### External DNS

TODO

### Load Balancer

TODO

[cert-manager-helm-install]: https://cert-manager.io/docs/installation/helm/
[cert-manager-verify]: https://cert-manager.io/docs/installation/kubectl/#verify
[terraform-provider-helm]: https://registry.terraform.io/providers/hashicorp/helm/latest/docs
[terraform-provider-k8s]: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
[vultr-webhook-cert-manager]: https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr
