# frankenstructure

The goal of this infrastructure project is to enable deploying all of my
monorepo applications quickly using shared resources.

To solve this, I chose an architecture relying on Kubernetes, so that I
can deploy containerized apps without needing to setup custom
infrastructure for each project. Sharing resources will allow me to
optimize costs.

## Tools

### Vultr

**API:**

- [Vultr API Documentation][vultr-api-docs]

### Terraform

**Providers:**

- [Vultr Terraform Provider][vultr-terraform-docs]
- [Kubernetes Terraform Provider][terraform-provider-k8s]
- [Helm Terraform Provider][terraform-provider-helm]

## Shared Resources

### Kubernetes Cluster (frank8s)

**Resources:**

- [Vultr Kubernetes Documentation][vultr-k8s-docs]
- [How to containerize Python web applications on Vultr][vultr-containerize-apps]
- [How to deploy a Vultr Kubernetes Engine Cluster][vultr-deploy-vke-cluster]

### Certificate Manager

**Resources:**

- [Install Cert Manager using Helm][cert-manager-helm-install]
- [Verify Cert Manager install][cert-manager-verify]
- [Vultr Webhook for Cert Manager][vultr-webhook-cert-manager]

[cert-manager-helm-install]: https://cert-manager.io/docs/installation/helm/
[cert-manager-verify]: https://cert-manager.io/docs/installation/kubectl/#verify
[terraform-provider-helm]: https://registry.terraform.io/providers/hashicorp/helm/latest/docs
[terraform-provider-k8s]: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
[vultr-api-docs]: https://www.vultr.com/api/
[vultr-containerize-apps]: https://docs.vultr.com/how-to-containerize-python-web-applications#prerequisites
[vultr-deploy-vke-cluster]: https://docs.vultr.com/vultr-kubernetes-engine#How_to_Deploy_a_VKE_Cluster
[vultr-k8s-docs]: https://docs.vultr.com/about-kubernetes-at-vultr
[vultr-terraform-docs]: https://registry.terraform.io/providers/vultr/vultr/latest/docs/
[vultr-webhook-cert-manager]: https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr
