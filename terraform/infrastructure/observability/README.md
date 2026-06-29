# observability infrastructure

Cluster-wide telemetry collection via the [opentelemetry-kube-stack][otel-kube-stack]
Helm release: the OTel operator plus three purpose-built collectors that
ship logs, metrics, traces, and synthetics to [Honeycomb][honeycomb].

**Requires:**

- A Honeycomb API key (`$HONEYCOMB_API_KEY`) — primary trace/query destination.
- Grafana Cloud credentials (`$GRAFANA_CLOUD_INSTANCE_ID`, `$GRAFANA_CLOUD_API_KEY`)
  for OTLP ingest + a GC SA token (`var.grafana_auth`) for alert IaC — GC is the
  alert-evaluation plane (see [Alerting](#alerting)).

**Resources:**

- `helm.tf` — the `opentelemetry-kube-stack` release + the `grafana-cloud` secret.
- `base_collector.tf` — shared receivers, processors, exporters, extensions (`defaultCRConfig`).
- `daemon_collector.tf`, `cluster_collector.tf`, `scrape_collector.tf` — per-collector overrides.
- `grafana_alerts.tf`, `honeycomb_alerts.tf` — alert rules, contact points, deadman wiring.
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
- **Destinations:** Honeycomb is primary (all telemetry). The Grafana Cloud
  exporter (`otlphttp/grafana-cloud`) carries the **alert signals only** —
  synthetics from the cluster collector and gateway RED (`spanmetrics` connector)
  from the daemon collector — so GC can evaluate them (see [Alerting](#alerting)).

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

### Alerting

Hybrid, **3 planes**: **Grafana Cloud evaluates**, **healthchecks.io arbitrates
liveness independently**, **Honeycomb stays the trace plane + a redundant gateway
SLI**. Splitting evaluation from the liveness arbiter means an outage of either
alerting backend is caught by the other.

#### Grafana Cloud (free tier) — alert-evaluation plane

Alert signals reach GC via the collectors' `otlphttp/grafana-cloud` exporter
(synthetics from the cluster collector; gateway RED via the `spanmetrics`
connector on the daemon collector). IaC: `grafana_alerts.tf` (grafana provider,
SA token `var.grafana_auth`). Folder **"Observability Alerts"**, rule group
`observability` (60s interval), **10 rules**:

| Rule                  | Condition                       | Metric / source                                                            |
| --------------------- | ------------------------------- | -------------------------------------------------------------------------- |
| SyntheticEndpointDown | availability down               | `httpcheck_status` by `http_url`                                           |
| SyntheticLatencyHigh  | p90 high                        | `httpcheck_duration_milliseconds` by `http_url`                            |
| SSLExpiringSoon       | < 7d left                       | `min by (tlscheck_x509_cn)(tlscheck_time_left_seconds)`                    |
| SSLExpiringCritical   | < 2d left                       | `min by (tlscheck_x509_cn)(tlscheck_time_left_seconds)`                    |
| GatewayErrorRate      | > 5% 5xx                        | spanmetrics `traces_span_metrics_calls_total`                              |
| GatewayLatencyHigh    | p90 > 500ms                     | spanmetrics `traces_span_metrics_duration_milliseconds_bucket`             |
| CollectorDownDaemon   | absent ≥ 10m (fleet-wide)       | `absent_over_time(otelcol_process_uptime_total{collector="daemon"}[10m])`  |
| CollectorDownCluster  | absent ≥ 10m                    | `absent_over_time(otelcol_process_uptime_total{collector="cluster"}[10m])` |
| CollectorDownScrape   | absent ≥ 10m                    | `absent_over_time(otelcol_process_uptime_total{collector="scrape"}[10m])`  |
| Watchdog              | `vector(1) > 0` (always firing) | deadman heartbeat                                                          |

Gateway rules scope to `service_name="ngf:gateway:prod-web"`.

> **Per-collector liveness.** The three `CollectorDown*` rules alert when a
> collector stops emitting its own heartbeat, independent of whether its data
> pipelines are flowing. Each tests
> `absent_over_time(otelcol_process_uptime_total{collector=...}[10m])` with
> **no_data = OK**, so a healthy collector (series present) stays silent and only
> a true absence fires. `CollectorDownDaemon` is a DaemonSet (one series per
> node), so it fires only on a **fleet-wide** outage. Collector self-telemetry is
> routed to GC by a `prometheus/self` receiver: the daemon and cluster collectors
> self-scrape `:8888`, while the scrape collector is **cross-scraped from the
> cluster collector** (its own targetAllocator rewrites prometheus receivers, so
> it cannot self-scrape).

> **spanmetrics sits _after_ the 20% sampler.** Absolute counts are therefore
> ÷5, but the **error ratio** (5xx / total) and **latency percentiles** are
> sampling-invariant — which is exactly what the gateway rules alert on.

**Notification** (`grafana_contact_point` / `grafana_notification_policy`):

- Default route → `email` contact point → **alerts@frank.sh** (GC hosted SMTP).
- Child matcher `alertname="Watchdog"` → `deadman_gc` webhook (pings
  healthchecks.io, below).

#### healthchecks.io — external liveness arbiter (deadman inversion)

Lives **outside** both GC and HC, so it catches an alerting backend going blind.
Each check expects a periodic ping; **absence** of the ping is the alert.

| Check              | Pinged by                            | Fires when                       |
| ------------------ | ------------------------------------ | -------------------------------- |
| `grafana-cloud-up` | GC Watchdog rule webhook, ~every 10m | GC stops evaluating → pings stop |
| `honeycomb-up`     | HC `HoneycombUpDeadman` trigger      | HC/pipeline dies → pings stop    |

#### Honeycomb (free tier) — trace/query plane + 2-trigger redundant subset

HC Free caps triggers at **2/team**, so HC hosts exactly two (IaC
`honeycomb_alerts.tf`):

- **GatewayServiceSLI** — `AVG(sli.gateway_success) < 0.99` → email. The derived
  column `sli.gateway_success` =
  `IF(AND(LT($http.status_code,500),LT($duration_ms,500)),1,0)`. Redundant with
  the GC gateway rules, on a fully independent backend.
- **HoneycombUpDeadman** — `COUNT > 0` on the `automate` dataset, `on_true`
  heartbeat → `honeycomb-up` webhook.

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

- **Alerting moved off Honeycomb triggers to Grafana Cloud.** Honeycomb Free caps
  triggers at 2/team, too few for the rule set we need. Alerting now evaluates on
  Grafana Cloud's free-tier alerting; HC retains a 2-trigger redundant subset
  (gateway SLI + a deadman). healthchecks.io arbitrates liveness of both backends
  independently. See [Alerting](#alerting).

- **Grafana Cloud routed for alert signals only.** `otlphttp/grafana-cloud` is
  attached to just the synthetics and gateway-spanmetrics pipelines — the inputs
  GC must evaluate — not the full telemetry stream. Honeycomb stays primary for
  traces/logs/metrics; we avoid double-billing bulk telemetry into GC while still
  giving the evaluation plane the signals it needs.

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
- **GitOps standard.** Stacks normally apply via CI on push to `main`. Local
  `tofu apply` is also safe — the Vultr S3 backend has `use_lockfile` enabled, so
  state locking serializes writes.
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
