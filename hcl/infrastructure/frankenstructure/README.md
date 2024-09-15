# frankenstructure

The goal of this infrastructure project is to enable deploying all of my
monorepo applications quickly using shared resources.

To solve this, I chose an architecture relying on Kubernetes, so that I
can deploy containerized apps without needing to setup custom
infrastructure for each project. Sharing resources will allow me to
optimize costs.

## References

- [How to containerize Python web applications on Vultr][vultr-containerize-apps]
- [How to deploy a Vultr Kubernetes Engine Cluster][vultr-deploy-vke-cluster]

[vultr-containerize-apps]: https://docs.vultr.com/how-to-containerize-python-web-applications#prerequisites
[vultr-deploy-vke-cluster]: https://docs.vultr.com/vultr-kubernetes-engine#How_to_Deploy_a_VKE_Cluster
