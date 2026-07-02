# Right-sizing frank8s workload resources (lean profile)

Per-workload CPU/memory `requests`/`limits` for every workload we deploy via
Terraform/OpenTofu, derived from 7-day production usage. This is the reference for
the values applied across `terraform/applications/*`, `terraform/infrastructure/*`,
and `fsharp/api/automate/terraform/`.

## 1. Context — why

The node pool alarmed at "81% CPU", which read as a capacity problem. It was not:
that figure is the sum of pod **CPU reservations** (`requests`), not actual usage.
Reservations are what the scheduler bin-packs against, so over-declared requests
burn schedulable capacity while the CPUs sit idle.

7-day actuals tell the real story:

- Cluster CPU **usage** ≈ **0.19 vCPU**, against ≈ **2.93 vCPU requested** (all pods,
  including VKE-managed system pods we do not control). Roughly a **15× over-reservation**.
- Of that, the workloads we manage in IaC requested ≈ **2.41 vCPU**.

So right-sizing is mostly about **reclaiming CPU reservations**. But it is
**bidirectional**: the same usage pull showed ≈ **9 workloads that under-declare
memory** (some declared none at all and ran unbounded). Those go **up** — an
under-declared pod is an eviction/OOM risk under node pressure, which is exactly the
failover scenario we care about. Trimming CPU without correcting memory would trade a
phantom CPU problem for a real memory one.

## 2. Reproducible method

There is **no metrics-server** in this cluster, so `kubectl top` is unavailable.
Usage lives in Honeycomb instead (the OTel daemon collector's `kubeletstats`
receiver ships it):

- Environment: **`prod`**
- Dataset: **`metrics`** — **not** the stale `k8s-metrics` dataset (ignore it).
- Gauges:
  - `k8s.pod.cpu.usage` — CPU in **cores**
  - `k8s.pod.memory.usage` — memory in **bytes**
- Filter: `k8s.cluster.name = frank8s`
- Group by: `k8s.namespace.name` + one of `k8s.deployment.name` /
  `k8s.daemonset.name` / `k8s.statefulset.name`
- Aggregate **AVG / P95 / MAX over 7 days** at the emitted **300s** interval.

Caveat baked into the recommendations: `k8s.pod.memory.usage` includes page
**cache**, so it overstates the true working set. Memory recommendations are
therefore kept **conservative** (we do not chase the raw MAX).

> This manual-query method is now backed by dashboards authored as Tofu in the
> `terraform/infrastructure/observability` stack:
>
> - **Honeycomb board — "Resource Right-Sizing · frank8s"**
>   (`honeycomb_boards.tf`): the raw 7-day CPU/memory **usage** gauges (P95 + MAX
>   by workload) this section describes, as a board instead of ad-hoc queries.
> - **Grafana Cloud dashboard — "frank8s · Utilization & Saturation"**
>   (`grafana_dashboards.tf`): the derived utilization **ratios**
>   (request/limit), memory working-set, node conditions, and CPU throttling —
>   the saturation signals that route to Grafana Cloud per the telemetry
>   deliverable, not to Honeycomb.
>
> Board/dashboard panel rendering is verified post-apply, and the Grafana metric
> names are derived from the OTel→Prometheus normalization (verify at apply).

## 3. Heuristic

Applied per workload, from its 7-day usage:

- **CPU request** = `max(P95 × 1.5, 10m)`
- **CPU limit** = **omitted everywhere.** CPU is compressible; a limit only adds
  throttling, which hurts tail latency for no capacity benefit (requests already
  protect the scheduler).
- **Memory request (lean)** = `max(P95 × 1.1, 24Mi)`
- **Memory limit** = `max(MAX × 1.5, memRequest)`. For small, flat-footprint
  controllers this collapses to `limit == request`, pinning a tight ceiling.

The daemon collector carries a higher CPU floor (25m) because it is the busiest
collector (host metrics + kubelet stats + log collection on every node).

## 4. Findings

- **CPU requests: ≈ 2.41 → 0.79 vCPU** across IaC-managed workloads — a reclaim of
  **≈ 1.6 vCPU**, which is what restores single-node CPU failover headroom (§6).
- **Memory: ≈ +480Mi** net. This is the intended, _correcting_ direction: ~9
  workloads under-declared (several declared nothing).
- **Worst over-provisioners** (huge reservation vs near-idle actuals): `miniflux`
  (0.1 CPU / 0.5Gi req → 10m / 64Mi), `ntfy`, `node-red` (**CPU only** — 100m → 10m;
  its memory is a separate, opposite story, raised below), the otel `scrape`
  statefulset (512Mi anti-OOM ceiling no longer needed — discovery is now scoped to
  a single PodMonitor), and `onepassword-connect`.
- **Under-provisioned — raised memory** (the risky direction, called out
  explicitly): `nginx-gateway` (control plane, 128→288Mi), `node-red` (memory
  **request** raised to 256Mi to honestly reflect ~210Mi live usage — node-red-chart
  0.33.0 defaults to 128Mi req / 512Mi lim, and that 512Mi limit is kept as the
  ceiling), `automate-api` (pod 192Mi, correcting the 64Mi api container),
  `external-dns` (32→96Mi), `cert-manager-cainjector` (32→96Mi).

## 5. Per-workload table (as applied)

CPU in millicores (`m`), memory in `Mi`. CPU limits omitted everywhere.

| workload (namespace)                                    | cpuReq | memReq | memLim | note                                                 |
| ------------------------------------------------------- | -----: | -----: | -----: | ---------------------------------------------------- |
| automate-api — `api` container (automate)               |     10 |    128 |    192 | pod totals 192Mi req / 320Mi lim across 2 containers |
| automate-api — `monitor` sidecar (automate)             |     10 |     64 |    128 | dotnet-monitor; dump/gcdump headroom                 |
| nginx-gateway control plane (gateway)                   |     10 |    288 |    352 | **RAISE** (mem); CPU req down 30→10m                 |
| cert-manager controller (gateway)                       |     10 |     64 |     64 |                                                      |
| cert-manager-cainjector (gateway)                       |     10 |     96 |     96 | **RAISE**                                            |
| cert-manager-webhook (gateway)                          |     10 |     32 |     48 | limit headroom on admission path (~99.5% of old)     |
| external-dns (gateway)                                  |     10 |     96 |     96 | **RAISE**                                            |
| external-secrets controller (external-secrets)          |     10 |    128 |    160 | busiest ESO component; limit headroom                |
| external-secrets webhook (external-secrets)             |     10 |     64 |     64 |                                                      |
| external-secrets cert-controller (external-secrets)     |     10 |     64 |     64 |                                                      |
| onepassword-connect — `connect-api` (external-secrets)  |     10 |     32 |     32 | pod target 64/64 split across 2 containers           |
| onepassword-connect — `connect-sync` (external-secrets) |     10 |     32 |     32 |                                                      |
| reloader (external-secrets)                             |     10 |     96 |     96 | ADDS a declaration (chart had none)                  |
| otel `scrape` collector — statefulset (observability)   |     10 |     64 |     64 |                                                      |
| otel target-allocator (observability)                   |     10 |     64 |     96 | limit headroom (~85% of old lim while fresh)         |
| otel operator (observability)                           |     10 |     64 |     96 | top of the operator/allocator range                  |
| otel cluster-stats collector (observability)            |     10 |    128 |    160 |                                                      |
| otel daemon-collector — daemonset (observability)       |     25 |    160 |    192 | higher CPU floor (busiest)                           |
| ntfy (ntfy)                                             |     10 |     32 |     32 |                                                      |
| miniflux (miniflux)                                     |     10 |     64 |     64 | worst over-provisioner                               |
| node-red (node-red)                                     |     10 |    256 |    512 | **CPU trim + honest mem req**; chart 512Mi lim kept  |
| httpbin (httpbin)                                       |     10 |     32 |     32 |                                                      |

### In-range / split choices (documented per the deliverable)

Where the target was a range or the pod hosts multiple containers, the choice made:

- **external-secrets (range 64–160Mi across 3 components):** controller **128Mi req
  / 160Mi lim** (it reconciles every `ExternalSecret` — the memory-heavy component —
  and gets limit headroom because it climbs over uptime on the ESO critical path);
  webhook and cert-controller **64Mi** each (lightweight admission / cert helpers),
  `limit == request`.
- **otel target-allocator / operator (range 64–96Mi):** the target-allocator gets
  **96Mi** limit (raised for headroom — it ran at ~85% of the old 64Mi limit while
  fresh); the operator gets **96Mi** limit (it holds more watch state reconciling the
  collector CRs). Both request 64Mi.
- **automate-api (2-container pod; pod totals 192Mi req / 320Mi lim):** split as
  `api` **128Mi/192Mi** (a .NET runtime, the larger share) + `monitor` sidecar
  **64Mi/128Mi** (dump/gcdump headroom). Requests sum to 192Mi; limits to 320Mi.
- **onepassword-connect (2-container pod; table target 64Mi req/lim):** this chart
  has **no pod-level `connect.resources`** — resources are per-container
  (`connect.api.resources`, `connect.sync.resources`). Split **evenly, 32Mi/32Mi**,
  summing to the pod target.

## 6. Failover verdict

Failover target: **one surviving node ≈ 1.8 vCPU / 3.62 Gi allocatable** must hold
the whole fleet.

- **CPU:** after right-sizing, total requests ≈ **550m** — comfortably inside 1.8
  vCPU. ✅ Single-node CPU failover is restored (it was not feasible at 2.41 vCPU of
  requests against a 1.8 vCPU survivor).
- **Memory:** total requests ≈ **3570Mi** against 3.62 Gi (≈ 3707Mi) allocatable —
  a **~137Mi (~4%) margin**. ⚠️ Tight, but acceptable: the old `kube-prometheus-stack`
  (≈ 900Mi) has been removed, so it no longer competes for the survivor's memory. In
  the review pass only node-red's memory _request_ rose (+64Mi: 192→256); the other
  headroom fixes were limit-only and do not change request-based scheduling. Watch
  this margin as workloads are added.

## 7. Scope / non-goals

- **VKE-managed pods are out of scope** and untouched: `calico-node`, `coredns`,
  `cluster-autoscaler`, `csi-*`, `kube-proxy`, `konnectivity-agent`. Vultr installs
  these; they are not in our IaC.
- The nginx **data-plane** deployment (per-Gateway `nginx` pods, e.g. `prod-web`)
  and cert-manager's `startupapicheck` **Job** are **not** in the target table and
  were left unchanged. The table's "nginx-gateway" row is the control-plane
  deployment (`k8s.deployment.name = nginx-gateway`).
- Only `resources` changed. Replica counts, affinity, images, and all other values
  are untouched in this change.
