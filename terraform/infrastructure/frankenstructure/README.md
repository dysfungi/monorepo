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

## Shared Resources

### S3-like Object Storage (frankenstorage)

**Resources:**

- [Vultr Object Storage Docs][vultr-object-storage-docs]

### Kubernetes Cluster (frank8s)

**Resources:**

- [Vultr Kubernetes Documentation][vultr-k8s-docs]
- [How to containerize Python web applications on Vultr][vultr-containerize-apps]
- [How to deploy a Vultr Kubernetes Engine Cluster][vultr-deploy-vke-cluster]

[vultr-api-docs]: https://www.vultr.com/api/
[vultr-containerize-apps]: https://docs.vultr.com/how-to-containerize-python-web-applications#prerequisites
[vultr-deploy-vke-cluster]: https://docs.vultr.com/vultr-kubernetes-engine#How_to_Deploy_a_VKE_Cluster
[vultr-k8s-docs]: https://docs.vultr.com/about-kubernetes-at-vultr
[vultr-object-storage-docs]: https://docs.vultr.com/vultr-object-storage
[vultr-terraform-docs]: https://registry.terraform.io/providers/vultr/vultr/latest/docs/
