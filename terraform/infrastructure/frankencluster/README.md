# frankencluster

The goal of this infrastructure project is to configure and setup the shared
Kubernetes cluster.

## Project APIs

### Tiers

_Inspired by [Deployment Environments][wiki-deploy-envs]._

- Production: `prod` -- serves end-users/clients
- Staging: `stage` -- mirror of production
- Testing: `test` -- where interface testing is performed
- Development: `dev` -- sandbox environment for development
- Local: `local` -- developer's desktop/workstation

## Tools

### GitHub Container Registry (GHCR.io)

Used here to download Helm Chart for Nginx-Gateway-Fabric.

- [Working with GitHub Packages][ghcr-docs-pkgs]

## Shared Resources

### Kubernetes Cluster (frank8s)

Owned by [frankenstructure](../frankenstructure).

**Requires:**

- Environment variable: `$VAR_TF_kubeconfig_path`

## Deployed Applications

### Monitoring

**Resources:**

- [Vultr blocks some ports][vultr-blocked-ports]

#### Dead Man's Switch

##### Healthcheck.io

**Resources:**

- [Healthchecks.io Documentation][healthchecks-io-docs]
- [Healthchecks.io | Terraform Provider][terraform-provider-healthchecksio]

#### Logs

##### Loki

_TODO_

**Resources:**

- [Grafana Loki Documentation][loki-docs]
- [Grafana Loki | Artifacthub][artifacthub-loki]

##### Promtail

_TODO_

**Resources:**

- [Grafana Promtail | Artifacthub][artifacthub-promtail]

#### Metrics

##### Kube Prometheus Operator

**Resources:**

- [Prometheus Operator | ArtifactHub][artifacthub-kube-prom]
- [Prometheus Operator API Docs][kube-prom-docs-api]
- [Kube Prometheus Helm Chart][kube-prom-helm-chart]

#### Synthetics

#### Prometheus Blackbox Exporter

**Resources:**

- [Prometheus Blackbox Exporter | ArtifactHub][artifacthub-prom-blackbox]
- [Prometheus Blackbox Exporter Helm Chart][prom-blackbox-helm-chart]
- [Prometheus Blackbox Exporter | Grafana Dashboard][grafana-dash-prom-blackbox-exporter]
  (id=`7587`)

### Tracing

_TODO_

**Resources:**

- [Grafana Tempo Documentation][tempo-docs]
- [Grafana Tempo | Artifacthub][artifacthub-tempo]

### k9s

**Resources:**

- [k9s CLI Docmuentation][k9s-docs]

<!--- REFERENCE LINKS --->

[artifacthub-kube-prom]: https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
[artifacthub-loki]: https://artifacthub.io/packages/helm/grafana/loki
[artifacthub-prom-blackbox]: https://artifacthub.io/packages/helm/prometheus-community/prometheus-blackbox-exporter
[artifacthub-promtail]: https://artifacthub.io/packages/helm/grafana/promtail
[artifacthub-tempo]: https://artifacthub.io/packages/helm/grafana/tempo
[ghcr-docs-pkgs]: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
[grafana-dash-prom-blackbox-exporter]: https://grafana.com/grafana/dashboards/7587-prometheus-blackbox-exporter/
[heathchecks-io-docs]: https://healthchecks.io/docs/
[k9s-docs]: https://k9scli.io/
[kube-prom-docs-api]: https://prometheus-operator.dev/docs/api-reference/api/
[kube-prom-helm-chart]: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
[loki-docs]: https://grafana.com/docs/loki/latest/
[prom-blackbox-helm-chart]: https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus-blackbox-exporter/README.md
[tempo-docs]: https://grafana.com/oss/tempo/
[terraform-provider-healthchecksio]: https://registry.terraform.io/providers/kristofferahl/healthchecksio/latest/docs
[vultr-blocked-ports]: https://docs.vultr.com/what-ports-are-blocked
[wiki-deploy-envs]: https://en.wikipedia.org/wiki/Deployment_environment#Environments
