# observability infrastructure

Cluster-wide telemetry collection via the [opentelemetry-kube-stack][otel-kube-stack]
Helm release: the OTel operator plus three purpose-built collectors that
ship logs, metrics, traces, and synthetics to [Honeycomb][honeycomb].

**Requires:**

- A Honeycomb API key (`$HONEYCOMB_API_KEY`) — primary destination.
- Grafana Cloud credentials (`$GRAFANA_CLOUD_INSTANCE_ID`, `$GRAFANA_CLOUD_API_KEY`) —
  credentialed but currently unrouted (see [Decisions](#decisions)).

**Resources:**

- `helm.tf` — the `opentelemetry-kube-stack` release + the `grafana-cloud` secret.
- `base_collector.tf` — shared receivers, processors, exporters, extensions (`defaultCRConfig`).
- `daemon_collector.tf`, `cluster_collector.tf`, `scrape_collector.tf` — per-collector overrides.
- `secrets.tf`, `variables.tf` — secret wiring and inputs.

### Architecture

One Helm release (`opentelemetry-kube-stack`) runs the OTel operator and three
collectors. Each collector owns a distinct slice of the telemetry surface:

- **daemon** (DaemonSet) — node-local signals:
  - app logs via `filelog` (preset) + `otlp` receiver.
  - traces via `otlp`, sampled at 20% (`probabilistic_sampler`).
  - kubelet metrics via `kubeletstats` @ 300s.
- **cluster** (Deployment, **1 replica** — singleton so `k8s_cluster` metrics
  are not double-counted):
  - cluster metrics via `k8s_cluster` @ 300s.
  - k8s events via `k8sobjects` (preset).
  - synthetics: `httpcheck` @ 60s + `tlscheck` @ 300s.
  - Pinned to `otel/opentelemetry-collector-contrib:0.123.0` — **the only
    image-pinned collector**, needed for `tlscheck` (see [Decisions](#decisions)).
- **scrape** (StatefulSet + targetAllocator) — Prometheus CR discovery scoped to
  the automate-api PodMonitor via label `otel-scrape=automate`; keeps only the
  dotnet exception metric (`filter/metrics-dotnet`). 512Mi limit.

Notes:

- App **traces** come from the OTel operator's **auto-instrumentation**
  (deployment annotation `instrumentation.opentelemetry.io/inject-dotnet`),
  **not** an in-app SDK.
- **Destinations:** Honeycomb is primary. The Grafana Cloud exporter
  (`otlphttp/grafana-cloud`) is defined and credentialed but **attached to no
  pipeline** — kept for easy re-enable.

### Signal catalog

Ground truth for every signal: receiver → collector·pipeline → exporter →
where it actually lands in Honeycomb.

| Signal                | Source / receiver         | Collector·pipeline         | Exporter (configured dataset header)         | Actual Honeycomb dataset                                            | Notes                                                               |
| --------------------- | ------------------------- | -------------------------- | -------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------- |
| app logs              | `filelog` + `otlp`        | daemon·logs                | `otlp/honeycomb-k8s-logs` (`k8s-logs`)       | **per-service, routed by `service.name`**                           | `transform/severity` parse + `filter/logs` WARN+ drop               |
| traces                | `otlp` (auto-instr)       | daemon·traces              | `otlp/honeycomb` (no header)                 | **default dataset by `service.name`** (e.g. `ngf-gateway-prod-web`) | 20% probabilistic sampling                                          |
| kubelet metrics       | `kubeletstats` @ 300s     | daemon·metrics             | `otlp/honeycomb-k8s-metrics` (`k8s-metrics`) | **`metrics`**                                                       | `filter/metrics-infra` allowlist                                    |
| cluster metrics       | `k8s_cluster` @ 300s      | cluster·metrics            | `otlp/honeycomb-k8s-metrics` (`k8s-metrics`) | **`metrics`**                                                       | allowlist: `k8s.container.restarts`, `k8s.pod.phase`, cpu/mem usage |
| dotnet exceptions     | `prometheus` scrape @ 30s | scrape·metrics             | `otlp/honeycomb-k8s-metrics` (`k8s-metrics`) | **`metrics`**                                                       | `systemruntime_exception_count` only                                |
| httpcheck (uptime)    | `httpcheck` @ 60s         | cluster·metrics/synthetics | `otlp/honeycomb-synthetics` (`synthetics`)   | **`metrics`**                                                       | by `http.url`                                                       |
| tlscheck (SSL expiry) | `tlscheck` @ 300s         | cluster·metrics/synthetics | `otlp/honeycomb-synthetics` (`synthetics`)   | **`metrics`**                                                       | `tlscheck.time_left` by `tlscheck.target`                           |
| k8s events            | `k8sobjects`              | cluster·logs               | `otlp/honeycomb-k8s-events` (`k8s-events`)   | **`k8s-events`**                                                    | `filter/logs` intentionally omitted (keep all events)               |

> **Dataset routing — the header is not the whole story.** Honeycomb routes OTLP
> **metrics** to the single `metrics` dataset regardless of the
> `x-honeycomb-dataset` header — so synthetics, kubelet, cluster, and dotnet
> metrics all land in `metrics`. **Logs** route per-service by `service.name`
> (the `k8s-logs` header is only the fallback bucket for unattributed logs).
> **Traces** route by `service.name`. Only **k8s events** actually use their
> header (`k8s-events`), because events carry no `service.name`.

### Cost & reduction levers

Honeycomb bills per datapoint (metrics) / per record (logs, traces). Current
levers and where they live:

- **Infra-metric interval 300s** — `kubeletstats` (`daemon_collector.tf`),
  `k8s_cluster` (`cluster_collector.tf`).
- **Trace sampling 20%** — `probabilistic_sampler` (`base_collector.tf`).
- **Synthetics intervals** — `httpcheck` 60s / `tlscheck` 300s (`cluster_collector.tf`).
- **`filelog.exclude` list** — drops Calico, OTel self-logs, httpbin, gpu-operator
  (`base_collector.tf`).
- **WARN+ log floor** — `filter/logs` (drop `severity_number < WARN`) +
  `transform/severity` (classify unparsed `severity_number == 0`) (`base_collector.tf`).
- **Single-line app logging at source** — the automate app uses
  `AddSimpleConsole(SingleLine = true)` so each log is one record, not two.

Result: ~953k → ~150k events/day (~84% reduction). The `metrics` dataset
(~98k/day) is now the floor — per-pod infra metrics dominate under Honeycomb's
per-datapoint model.

### Decisions

ADR-lite, 2026-06.

- **Grafana Cloud kept but unrouted.** Removed `otlphttp/grafana-cloud` from all
  pipelines while retaining the exporter definition and credentials. Re-enabling
  is a one-line change (add it back to a pipeline's `exporters`). We chose
  Honeycomb-primary without burning the existing Grafana Cloud integration, so
  the fallback stays cheap to reach for.

- **contrib 0.123.0 on the cluster collector only.** `tlscheck` is not compiled
  into the published k8s/contrib collector images until 0.123.0 (upstream
  `opentelemetry-collector-contrib` #38749 — manifest gap). We accepted a +3-minor
  skew from the 0.120 operator default, scoped to the single collector that needs
  it, rather than upgrading every collector or dropping TLS-expiry monitoring.

- **Single-line console logging at the app source.** The default ASP.NET 2-line
  log format made OTel split each entry into a prefixed line plus an
  unclassifiable indented continuation (~275k orphan records/day). We fixed it at
  the source (`AddSimpleConsole`, `SingleLine = true`) instead of bolting on a
  downstream multiline-recombine operator — deleting the problem class rather than
  patching its symptoms.

- **Infra metrics in Honeycomb (cost tradeoff).** Per the Honeycomb-primary goal
  we keep infra metrics here even though they are the dominant remaining cost
  under per-datapoint billing. Mitigated with a 300s collection interval and a
  tight allowlist (`filter/metrics-infra`) rather than diverting them to Grafana
  Cloud, which would re-split observability across two backends.

- **Scrape collector scoped to automate-only.** The targetAllocator
  `podMonitorSelector` is keyed to label `otel-scrape=automate` (the prometheusCR
  integration has no namespace selector). This prevents the collector from
  discovering and scraping every PodMonitor in the cluster.

### Operations / gotchas

- **`tofu validate` does not catch runtime config errors.** OTTL syntax, invalid
  k8s label values, and missing-image-component errors only surface when the
  collector starts. **Always** verify pod health after a change:
  `kubectl -n observability get pods` (no `CrashLoopBackOff`).
- **GitOps only.** Stacks apply via CI on push to `main`. Do not `tofu apply`
  locally — the Vultr S3 backend has `use_lockfile` enabled. Local
  `init` / `validate` / `plan` for authoring is fine.
- **Provider-lock skew.** The committed `kubernetes` provider lock (`~> 2.32`)
  lags the version that wrote state (2.38), so local `tofu plan` needs
  `init -upgrade`; CI applies fine.
- **Re-measure volume** with the Honeycomb MCP: per-dataset `COUNT` (events) /
  `COUNT_DATAPOINTS` (metrics) over a recent window.

### Resources

- [opentelemetry-kube-stack chart][otel-kube-stack]
- [opentelemetry-collector-contrib][otel-contrib]
- [Honeycomb — sending data with OTLP][honeycomb-otlp]
- [Honeycomb — datasets & dataset routing][honeycomb-datasets]

<!--- REFERENCE LINKS --->

[honeycomb]: https://www.honeycomb.io/
[honeycomb-datasets]: https://docs.honeycomb.io/get-started/best-practices/structured-logging/
[honeycomb-otlp]: https://docs.honeycomb.io/send-data/opentelemetry/
[otel-contrib]: https://github.com/open-telemetry/opentelemetry-collector-contrib
[otel-kube-stack]: https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-kube-stack
