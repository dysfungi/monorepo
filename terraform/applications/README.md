# Applications

Tofu-managed workloads that run _on_ the `frank8s` cluster (as opposed to the
cluster/infra itself, which lives under [`../infrastructure`](../infrastructure)).

## Node-loss resilience convention

**App Deployments default to `replicas >= 2` and spread those replicas across
nodes**, so losing a single node cannot take a whole service offline. This is the
repo-wide convention referenced from the root `AGENTS.md` (Kubernetes section).

### The rule

Every app Deployment should:

1. Run **at least 2 replicas** (subject to the node budget — see right-sizing;
   more replicas than nodes just pile onto shared nodes and waste headroom).
2. Carry a **`topologySpreadConstraints`** entry:

   | field               | value                                      |
   | ------------------- | ------------------------------------------ |
   | `topologyKey`       | `kubernetes.io/hostname`                   |
   | `maxSkew`           | `1`                                        |
   | `whenUnsatisfiable` | `ScheduleAnyway`                           |
   | `labelSelector`     | the workload's **own** rendered pod labels |

**Goal:** at least one replica of each service survives a node loss. This is a
_resilience_ convention, not an autoscaling one — it does not add capacity, it just
refuses to let the scheduler stack a service's only replicas onto one node.

### `whenUnsatisfiable=ScheduleAnyway` is best-effort by design

`ScheduleAnyway` (soft), **not** `DoNotSchedule` (hard). Under normal conditions the
scheduler honours the spread and places replicas on distinct nodes. But if the
cluster is temporarily down to a single schedulable node (a node is draining, a pool
is mid-resize, etc.), a hard constraint would leave the second replica **Pending** —
trading availability for a scheduling ideal. Soft spreading keeps both replicas
running in that degraded window and re-balances once a second node is available
again. We accept "usually spread, never stranded" over "always spread or not at all".

### Pin `labelSelector.matchLabels` — the silent-failure trap

Most charts pass `topologySpreadConstraints` through to the pod spec **raw** and do
**not** auto-fill the `labelSelector`. That leaves two failure modes:

- `labelSelector: nil` (omitted) → matches **nothing** → the constraint is a
  **no-op** (replicas can still land on one node; looks configured but isn't).
- `labelSelector: {}` (empty) → matches **every pod in the namespace** → skew is
  computed against unrelated workloads → **wrong** spreading.

So always pin `matchLabels` to the **minimal set of the workload's own rendered pod
labels** that uniquely identifies it. Verify the rendered manifest (`helm template …`
or `kubectl get pod -l … --show-labels`) — the rendered `labelSelector.matchLabels`
being correct, non-empty, and workload-specific is the real gate on this convention.
Chart value **paths differ** (e.g. cert-manager uses per-component
`cainjector.topologySpreadConstraints` / `webhook.…`; NGF uses
`nginxGateway.topologySpreadConstraints`; the miniflux `bjw-s/common` 1.5.1 chart
renders pod options at the **top level**), so confirm the path per chart too.

### Charts that can't express `topologySpreadConstraints`

Some charts (e.g. `matheusfm/httpbin`) don't surface `topologySpreadConstraints` at
all. **Do not skip** — skipping leaves a 2-replica service pinnable to one node, the
exact failure this convention prevents. Instead fall back to a soft `podAntiAffinity`
(`preferredDuringSchedulingIgnoredDuringExecution`) on the same
`topologyKey=kubernetes.io/hostname`, via whatever `affinity` key the chart _does_
accept. Same intent (keep replicas off the same node), expressed through the knob the
chart exposes.

### Singleton / stateful exceptions

Workloads that **cannot** run more than one replica are explicit, documented
exceptions:

- A **single-writer RWO volume** (only one pod can mount it read-write), or
- **No cross-instance clustering** (running >1 replica would corrupt state or
  double-process work).

[**ntfy**](ntfy) is the canonical example: SQLite on an RWO volume, no cross-instance
message fan-out, so the chart hardcodes `replicas=1` + `Recreate`. Such workloads
stay at 1 replica by design and document _why_ at the point of definition (see
`ntfy/helm.tf` and `ntfy/README.md`). A node loss makes them briefly unavailable
until the pod reschedules — accepted for best-effort services.

## Current status

| workload | replicas | spreading mechanism                                 |
| -------- | -------- | --------------------------------------------------- |
| httpbin  | 2        | soft `podAntiAffinity` (chart lacks topologySpread) |
| miniflux | 2        | top-level `topologySpreadConstraints`               |
| ntfy     | 1        | **exception** — single-writer RWO volume            |

Cluster/infra workloads follow the same convention where they run >1 replica — see
the NGF control plane (`nginxGateway`) and cert-manager `cainjector` / `webhook` in
[`../infrastructure/gateway/helm.tf`](../infrastructure/gateway/helm.tf).
