# gateway infrastructure

### Certificate Manager

**Requires:**

- Environment variable: `$VAR_TF_cloudflare_api_token`

**Resources:**

- [Cert Manager | ArtifactHub][artifacthub-cert-manager]
- [Install Cert Manager using Helm][cert-manager-helm-install]
- [Verify Cert Manager install][cert-manager-verify]
- [Vultr Webhook for Cert Manager | ArtifactHub][artifacthub-cert-manager-vultr-webhook]
- [Cert Manager with Cloudflare][cert-manager-cloudflare]

### Gateway API

**Gateways:**

- `prod-web`: intended for production tier HTTP requests
  - Only allows routes from namespaces with label `tier=prod`
- `stage-web`: intended for staging tier HTTP requests
  - Only allows routes from namespaces with label `tier=stage`

**Project API:**

- `HTTPRoute`

**Resources:**

- [Kubernetes Gateway API][k8s-gateway-api]
- [Gateway API Docs][gateway-api-docs]
- [Nginx Gateway Fabric - Helm Install][ngf-helm-install]
- [Nginx Gateway Fabric - Routing Traffic to Apps][ngf-routing]

### Load Balancer

**Resources:**

- [Vultr VKE Load Balancer][vultr-vke-lb]
- [Kubernetes - Service - Load Balancer][k8s-docs-svc-lb]

### External DNS

- [External DNS | ArtifactHub][artifacthub-external-dns]
- [External DNS with Cloudflare][external-dns-cloudflare]

<!--- REFERENCE LINKS --->

[artifacthub-cert-manager-vultr-webhook]: https://artifacthub.io/packages/helm/vultr/cert-manager-webhook-vultr
[artifacthub-cert-manager]: https://artifacthub.io/packages/helm/cert-manager/cert-manager
[artifacthub-external-dns]: https://artifacthub.io/packages/helm/external-dns/external-dns
[cert-manager-cloudflare]: https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/#api-tokens
[cert-manager-helm-install]: https://cert-manager.io/docs/installation/helm/
[cert-manager-verify]: https://cert-manager.io/docs/installation/kubectl/#verify
[external-dns-cloudflare]: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/cloudflare.md#using-helm
[gateway-api-docs]: https://gateway-api.sigs.k8s.io/implementations/#nginx-gateway-fabric
[k8s-docs-svc-lb]: https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer
[k8s-gateway-api]: https://kubernetes.io/docs/concepts/services-networking/gateway/
[ngf-helm-install]: https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/
[ngf-routing]: https://docs.nginx.com/nginx-gateway-fabric/how-to/traffic-management/routing-traffic-to-your-app/
[vultr-vke-lb]: https://docs.vultr.com/vultr-kubernetes-engine#vke-load-balancer
