# Node-pool migration runbook (Deliverable 4b — hybrid topology)

Zero-downtime, **LOCAL** migration of the `frank8s` VKE cluster from the
single-purpose `infrastructure` pool to a hybrid topology:

| Pool                 | Plan (AMD only)        | Size   | min/max | Role                                |
| -------------------- | ---------------------- | ------ | ------- | ----------------------------------- |
| `default` (inline)   | `vhp-2c-4gb-amd` ($24) | medium | 1 / 1   | stable 4 GB node (label immutable)  |
| `vhp-amd.small`      | `vhp-1c-2gb-amd` ($12) | small  | 2 / 4   | elastic workhorse, redundancy floor |
| ~~`infrastructure`~~ | ~~`vhp-2c-4gb-amd`~~   | —      | —       | **DELETED** by this migration       |

End state: **3 nodes** (2 small + 1 medium), **~$48/mo**, autoscaler backfills
`small` on node loss within minutes. Realizes the HYBRID topology from the
right-sizing plan; pair with the right-sizing work (PR #21) so the 2 GB nodes
have request/limit headroom.

The end-state HCL is already committed in
`terraform/infrastructure/frankenstructure/vultr_kubernetes.tf`. This runbook is
how you converge the live cluster onto it **incrementally**, one `-target` at a
time — never in a single combined apply.

---

## Preamble — safety rules (read before touching anything)

- **AMD only.** Every pool uses a `vhp-*-amd` plan. Never substitute `vc2`/Intel.
- **Local apply writes to the SAME remote state CI uses.** A local `tofu apply`
  is not a sandbox — it mutates the shared Vultr S3 state that the CI/CD pipeline
  reconciles on every push to `main`. **After each applied step, commit the
  matching HCL to `main`** so the next CI run sees no drift. If you apply locally
  but don't land the HCL, the next CI apply will try to revert your change.
- **DO NOT let CI apply this PR as one shot.** The PR that carries this HCL is
  marked DO-NOT-CI-MERGE. A combined apply (add small + rescale default + destroy
  infrastructure, all at once) could destroy the `infrastructure` node **before**
  its pods have drained — an outage. CI merge is only safe _after_ the local
  migration below, as a state-reconciling no-op.
- **`node_quantity = 0` is schema-REJECTED** (`IntAtLeast(1)`), and `min_nodes = 0`
  does NOT give real scale-to-zero (the Vultr API floors node counts at 1). You
  **cannot** empty a pool with tofu. Empty a pool with `kubectl cordon` + `drain`,
  then delete the pool resource.
- **Every `tofu plan` must show ONLY pool-level changes** — a pool add, a
  min/max in-place update (`~`), or a pool destroy. If ANY plan shows the cluster
  resource `vultr_kubernetes.k8s` being replaced (`-/+` / "forces replacement"),
  **STOP** — that is a cluster rebuild, not a pool change. Do not apply.
- **`*.frank.sh` TLS checks:** stock macOS `/usr/bin/curl` (LibreSSL) fails NGF
  `*.frank.sh` endpoints with an "unrecognized name" SNI error. Use Homebrew curl
  (`$(brew --prefix curl)/bin/curl`) or `openssl s_client` for health checks.

All commands run from the stack directory:

```bash
cd terraform/infrastructure/frankenstructure
```

---

## Step 0 — baseline

Capture the starting state so you can compare after each step.

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -v -E 'Running|Completed'   # should be empty-ish
tofu init            # ensure providers/state are current (real backend, needs creds)
tofu plan            # sanity: review the FULL pending delta before you start
```

The full `tofu plan` should show: **+ add** `vultr_kubernetes_node_pools.small`,
**~ update** `vultr_kubernetes.k8s` (default pool max_nodes 2->1), **- destroy**
`vultr_kubernetes_node_pools.infrastructure`. Confirm ZERO cluster replacement.
If it shows a cluster `-/+`, STOP.

Note the `infrastructure` node name for Step 2:

```bash
kubectl get nodes -l vke.vultr.com/node-pool=infrastructure -o name
# (label key may differ; cross-check `kubectl get nodes --show-labels`)
```

---

## Step 1 — add the `vhp-amd.small` pool + rescale `default`

Add the new elastic capacity **first**, so there is somewhere for the
`infrastructure` pods to land before we drain them.

```bash
# 1a. Review, then apply ONLY the new small pool.
tofu plan  -target=vultr_kubernetes_node_pools.small     # expect: + add, nothing else
tofu apply -target=vultr_kubernetes_node_pools.small

# 1b. Rescale the inline default pool to min1/max1 (in-place update on the cluster).
tofu plan  -target=vultr_kubernetes.k8s     # expect: ~ in-place update (max_nodes 2->1); NO -/+
tofu apply -target=vultr_kubernetes.k8s
```

- The `-target=vultr_kubernetes.k8s` plan **must** be an in-place `~` update
  (only `max_nodes` changing, plus the new `lifecycle` ignore). If it shows
  `-/+` (replacement), STOP — do not apply; the medium node must not be rebuilt.
- **If `tofu apply` rejects the `vhp-amd.small` label** (invalid-charset error on
  the `.`), fall back: edit the HCL `label = "vhp-amd-small"` (all-dash), re-run
  `tofu plan -target=...`, re-apply. Keep `tag = "small"`.

Wait for the 2 small nodes to be `Ready`:

```bash
kubectl get nodes -w        # Ctrl-C once 2x vhp-amd.small nodes show Ready
```

**Commit the HCL for what you just applied to `main`** (small pool add + default
rescale). At this point the live cluster has: 2 small + 1 medium + 1 infra = 4 nodes.

---

## Step 2 — drain the `infrastructure` node

Move all workloads off `infrastructure` onto the small/medium nodes. No pool
change here — pure `kubectl`.

```bash
INFRA=$(kubectl get nodes -l vke.vultr.com/node-pool=infrastructure -o jsonpath='{.items[0].metadata.name}')
kubectl cordon "$INFRA"
kubectl drain  "$INFRA" --ignore-daemonsets --delete-emptydir-data
```

`drain` evicts pods gracefully; they reschedule onto small/medium. Verify a
clean landing:

```bash
kubectl get pods -A -o wide | grep -i pending      # MUST be empty (0 Pending)
kubectl get pods -A -o wide | grep -v "$INFRA"      # infra-hosted pods now elsewhere
```

Confirm the infra-hosted control-plane workloads are `Running` on other nodes:
**NGINX Gateway Fabric (NGF), cert-manager, External Secrets Operator (ESO),
1Password Connect, and the OTel collector.** Then confirm ingress still serves:

```bash
# Homebrew curl (LibreSSL stock curl fails *.frank.sh SNI):
$(brew --prefix curl)/bin/curl -sSI https://<some-app>.frank.sh | head -1
# or: openssl s_client -connect <host>:443 -servername <some-app>.frank.sh </dev/null
```

If anything is stuck `Pending` (insufficient capacity on 2 GB small nodes),
**pause** — the autoscaler should add a small node (max 4), or temporarily bump
the medium's `max_nodes` back to 2. Do not proceed to Step 3 until 0 Pending.

---

## Step 3 — delete the `infrastructure` pool

The node is drained and empty; now remove the pool resource. The HCL block is
**already deleted** in this branch, so this is just applying that deletion.

```bash
tofu plan  -target=vultr_kubernetes_node_pools.infrastructure   # expect: - destroy, ONLY that pool
tofu apply -target=vultr_kubernetes_node_pools.infrastructure
```

The plan must show the destroy of **only** `vultr_kubernetes_node_pools.infrastructure`
— no cluster replacement, no other pool touched. Verify the end state:

```bash
kubectl get nodes        # expect exactly 3: 2x vhp-amd.small + 1x default(medium)
kubectl get pods -A -o wide | grep -i pending    # empty
```

**Commit the HCL** (the `infrastructure` block removal) to `main`.

---

## Step 4 (OPTIONAL) — dot-label proof + `default` rename

Skip unless you specifically want `default` relabeled to `vhp-amd.medium`. The
inline `default` label is immutable in-place (see the HCL comment), and a rename
would force a pool replacement = cluster rebuild. **Never rebuild the cluster for
a cosmetic name.**

If you still want it, prove it's rebuild-free on a **throwaway** pool first:

1. Add a scratch standalone pool with a dotted label (e.g. `resource
"vultr_kubernetes_node_pools" "scratch"` with `label = "scratch.test"`,
   `min_nodes = 1`, `max_nodes = 1`). `tofu apply -target=...scratch`.
   - If the API rejects the dot here too, the dot is unusable — stop, keep dashes.
2. Change the scratch pool's `label` and `tofu plan -target=...scratch`.
   - If the plan is an **in-place `~` update** (not `-/+`), then a standalone pool
     label IS mutable — but the **inline** pool still is not (different code path).
   - If it shows `-/+`, labels force replacement — abandon the rename entirely.
3. Destroy the scratch pool (`kubectl drain` if it got a node, then remove the
   block + apply). Leave `default` as-is; a rename is not worth a rebuild.

---

## Post-migration

- **Land all HCL on `main`.** After the final commit, the working HCL and live
  state match. Confirm the **next CI apply is a no-op** (an empty plan) — this is
  what makes the DO-NOT-CI-MERGE PR safe to merge as a reconcile.
- **End state:** 3-node cluster (2x `vhp-amd.small` 2 GB + 1x `default` 4 GB
  medium), ~$48/mo, redundancy floor of 3, autoscaler backfills `small` (up to 4)
  within minutes on node loss.
- **Cross-reference:** this is the HYBRID topology from the right-sizing plan.
  Pair with the workload right-sizing (PR #21) so requests/limits fit the 2 GB
  small nodes with headroom.
