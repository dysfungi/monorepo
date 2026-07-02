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
  the automate-api PodMonitor via label `otel-scrape=automate` (dotnet exception
  metric via `filter/metrics-dotnet` → HC), plus a static `prometheus/cadvisor`
  kubelet scrape for CFS throttling → GC. 128Mi limit (raised from 64Mi for the
  full-cluster cAdvisor parse burst).

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

| Signal                           | Source / receiver           | Collector·pipeline          | Exporter (configured dataset header)         | Actual Honeycomb dataset                                            | Notes                                                               |
| -------------------------------- | --------------------------- | --------------------------- | -------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------- |
| app logs                         | `filelog` + `otlp`          | daemon·logs                 | `otlp/honeycomb-k8s-logs` (`k8s-logs`)       | **per-service, routed by `service.name`**                           | `transform/severity` parse + `filter/logs` WARN+ drop               |
| traces                           | `otlp` (auto-instr)         | daemon·traces               | `otlp/honeycomb` (no header)                 | **default dataset by `service.name`** (e.g. `ngf-gateway-prod-web`) | 20% probabilistic sampling                                          |
| kubelet metrics                  | `kubeletstats` @ 300s       | daemon·metrics              | `otlp/honeycomb-k8s-metrics` (`k8s-metrics`) | **`metrics`**                                                       | `filter/metrics-infra` allowlist                                    |
| cluster metrics                  | `k8s_cluster` @ 300s        | cluster·metrics             | `otlp/honeycomb-k8s-metrics` (`k8s-metrics`) | **`metrics`**                                                       | allowlist: `k8s.container.restarts`, `k8s.pod.phase`, cpu/mem usage |
| dotnet exceptions                | `prometheus` scrape @ 30s   | scrape·metrics              | `otlp/honeycomb-k8s-metrics` (`k8s-metrics`) | **`metrics`**                                                       | `systemruntime_exception_count` only                                |
| httpcheck (uptime)               | `httpcheck` @ 60s           | cluster·metrics/synthetics  | `otlp/honeycomb-synthetics` (`synthetics`)   | **`metrics`**                                                       | by `http.url`                                                       |
| tlscheck (SSL expiry)            | `tlscheck` @ 300s           | cluster·metrics/synthetics  | `otlp/honeycomb-synthetics` (`synthetics`)   | **`metrics`**                                                       | `tlscheck.time_left` by `tlscheck.target`                           |
| k8s events                       | `k8sobjects`                | cluster·logs                | `otlp/honeycomb-k8s-events` (`k8s-events`)   | **`k8s-events`**                                                    | `filter/logs` intentionally omitted (keep all events)               |
| utilization (node/pod/container) | `kubeletstats` @ 300s       | daemon·metrics/utilization  | `otlphttp/grafana-cloud`                     | **— (Grafana Cloud)**                                               | `filter/metrics-utilization` allowlist; HC pipeline untouched       |
| utilization (cluster)            | `k8s_cluster` @ 300s        | cluster·metrics/utilization | `otlphttp/grafana-cloud`                     | **— (Grafana Cloud)**                                               | req/limit denominators, node conditions, workload readiness         |
| cadvisor throttling              | `prometheus/cadvisor` @ 60s | scrape·metrics/cadvisor     | `otlphttp/grafana-cloud`                     | **— (Grafana Cloud)**                                               | `filter/metrics-cadvisor`: `container_cpu_cfs_throttled_*`          |

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
> cluster collector**. (Historically this was believed necessary because "the
> targetAllocator rewrites prometheus receivers"; the allocator in fact rewrites
> ONLY the receiver keyed exactly `prometheus`, so a sibling `prometheus/self`
> there would survive — see the TA-safety note in `scrape_collector.tf`. The
> cross-scrape is kept as-is since it works.)

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

### Telemetry catalog

Ground truth for **which metric class lands where and why**. This table is the
guard against a future cost pass re-pruning the useful signals: read the
destination rationale below before touching any allowlist.

> **Why the HC/GC split — READ THIS before re-pruning.** Honeycomb Free bills per
> **datapoint**: every metric sample emitted is billable, so high-cardinality /
> per-container series are expensive, and `filter/metrics-infra` deliberately keeps
> the HC metric set tiny. Grafana Cloud Free bills per **active series** (10k
> included) with unlimited datapoints per series — once a series exists its samples
> are effectively free. This fleet sits far under 10k active series, so the useful
> utilization / saturation metrics route to **GC** (where they cost ≈nothing)
> instead of HC (where a prior cost pass pruned them under per-datapoint billing).
> **Do NOT move the GC-routed classes back into the HC allowlist to "consolidate"** —
> that reintroduces the exact per-datapoint cost this split exists to avoid.

| Metric class                                                                              | Dest        | Use case                                   | Kept / dropped — why                                                             |
| ----------------------------------------------------------------------------------------- | ----------- | ------------------------------------------ | -------------------------------------------------------------------------------- |
| node/pod CPU+mem usage (`k8s.{node,pod}.{cpu,memory}.usage`)                              | **HC**      | baseline node/pod resource use             | KEPT in HC allowlist (`filter/metrics-infra`) — small, high-value                |
| container restarts, pod phase (`k8s.container.restarts`, `k8s.pod.phase`)                 | **HC**      | crashloop / pod health                     | KEPT in HC allowlist                                                             |
| dotnet exceptions (`systemruntime_exception_count`)                                       | **HC**      | app error signal                           | KEPT (scrape, `filter/metrics-dotnet`)                                           |
| pod utilization ratios (`k8s.pod.{cpu,memory}_{request,limit}_utilization`)               | **GC**      | right-sizing headroom, throttle risk       | RE-ENABLED → GC. Computed on daemon, dropped by HC allowlist; per-series ≈free   |
| container cpu/mem (`container.cpu.usage`, `container.memory.{usage,working_set}`)         | **GC**      | per-container hotspots                     | GC-only — higher cardinality than pod-level; `container.cpu.usage` newly enabled |
| pod memory working set (`k8s.pod.memory.working_set`)                                     | **GC**      | true mem pressure vs page cache            | GC — already emitted, was HC-dropped                                             |
| filesystem usage/capacity (`k8s.node.filesystem.*`, `container.filesystem.*`)             | **GC**      | disk-fill prediction                       | GC — already emitted, was HC-dropped                                             |
| container request/limit denominators (`k8s.container.{cpu,memory}_{request,limit}`)       | **GC**      | right-sizing math (the ratio denominators) | GC — from `k8s_cluster`, was HC-dropped                                          |
| node conditions (`k8s.node.condition_{ready,memory_pressure,disk_pressure,pid_pressure}`) | **GC**      | node health                                | GC — pressures need `node_conditions_to_report` expanded on `k8s_cluster`        |
| workload readiness (`k8s.{deployment,daemonset,statefulset,job,hpa}.*`)                   | **GC**      | rollout / capacity health                  | GC — from `k8s_cluster`, was HC-dropped                                          |
| cAdvisor CPU throttling (`container_cpu_cfs_throttled_*`, `_periods_total`)               | **GC**      | #1 CPU-saturation signal                   | RE-ENABLED via new `prometheus/cadvisor` scrape → GC (`filter/metrics-cadvisor`) |
| hostmetrics `system.*`                                                                    | **dropped** | (redundant)                                | DROPPED at source — preset disabled; duplicated kubeletstats `k8s.node.*`        |
| `k8s.{node,pod}.uptime`                                                                   | **dropped** | low value                                  | enable REMOVED — was allowlisted-out (no-op) anyway                              |
| replicaset desired/available (`k8s.replicaset.*`)                                         | **dropped** | high-volume, low-signal                    | disabled at `k8s_cluster` receiver (pre-existing)                                |
| app logs (WARN+), traces (20%), k8s events                                                | **HC**      | debugging / audit                          | see [Signal catalog](#signal-catalog) + reduction levers above                   |
| synthetics (httpcheck/tlscheck), gateway RED (spanmetrics)                                | **HC + GC** | alert signals                              | dual-routed so GC can evaluate alerts (see [Alerting](#alerting))                |

#### Post-deploy verification

Collector config (receivers, pipelines, OTTL) is **not** `tofu validate`-checked —
`tofu validate` only proves the HCL is well-formed. GitOps applies on merge; after
the deploy lands, confirm:

1. **Collectors healthy + GC receiving the new series.** `kubectl -n observability
get pods` shows no `CrashLoopBackOff`, and the re-enabled utilization/cadvisor
   series appear in Grafana Cloud (Explore the `metrics/utilization` +
   `metrics/cadvisor` classes from the [catalog](#telemetry-catalog) above).
2. **`prometheus/cadvisor` scrape actually works (F2).** Confirm the receiver
   survives the operator's targetAllocator in the rendered `OpenTelemetryCollector`
   CR (only the exact-keyed `prometheus` receiver is rewritten; the
   `prometheus/cadvisor` sibling must remain a static scrape), and that the scrape
   StatefulSet pod reaches the kubelet at `:10250` (`/metrics/cadvisor`) — check its
   logs for scrape errors / TLS or RBAC (`nodes/metrics`) failures.
3. **GC active-series budget (F3).** Verify Grafana Cloud active-series count stays
   under the 10k free-tier cap after the additive series land; the scrape-level
   keep-filter and the `metrics/cadvisor` allowlist should hold cAdvisor to the 3
   CFS families.

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

- **Infra metrics split across Honeycomb and Grafana Cloud (cost-driven).** The
  small, high-value core (`filter/metrics-infra`: node/pod cpu+mem usage, restarts,
  pod phase) stays in Honeycomb at a 300s interval — cheap enough under
  per-datapoint billing and co-located with traces/logs. The broader
  utilization/saturation set a prior pass over-pruned (per-pod ratios, per-container
  cpu/mem, node conditions, workload readiness, CFS throttling) now routes to
  **Grafana Cloud** via parallel `metrics/utilization` + `metrics/cadvisor`
  pipelines: GC's per-active-series billing (10k free, fleet well under) makes these
  effectively free where HC's per-datapoint model made them the dominant cost. The
  HC allowlist + pipelines are untouched, so HC volume stays flat (~150k/day); the
  re-enabled signals are additive on GC. See [Telemetry catalog](#telemetry-catalog).

- **Scrape collector scoped to automate-only.** The targetAllocator
  `podMonitorSelector` is keyed to label `otel-scrape=automate` (the prometheusCR
  integration has no namespace selector). This prevents the collector from
  discovering and scraping every PodMonitor in the cluster.

- **`metrics/cadvisor` pipeline kept deliberately lean.** It runs no
  `k8sattributes`/`resourcedetection` enrichment — that would add memory and
  cardinality for no gain, since the CFS throttle series already carry the
  Prometheus `pod`/`container`/`namespace` labels needed to correlate them back to
  workloads. Enrichment is reserved for the OTLP paths that lack those labels.

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
