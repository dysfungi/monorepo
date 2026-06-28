# terraform

Infrastructure, applications, and shared modules managed with
[OpenTofu](https://opentofu.org/). Strictly prefer `tofu` over `terraform`
for all operations (`fmt`, `validate`, `plan`, `apply`).

```
terraform/applications/
terraform/infrastructure/frankenstructure
terraform/modules/
```

## state backend & locking

Remote state lives in **Vultr Object Storage** (S3-compatible): bucket
`frankenstructure`, endpoint `sjc1.vultrobjects.com`, region `us-west-1`.
Each stack uses its own key, `terraform/<stack>.tfstate`, declared per-stack in
its `backend "s3"` block — 8 stacks total (the 7 under `terraform/` plus
`fsharp/api/automate/terraform`).

### locking

State locking is **enabled** via `use_lockfile = true` on every S3 backend.
OpenTofu writes a `<key>.tflock` object using an S3 **conditional write**
(`If-None-Match: *`) for atomic compare-and-swap locking — no DynamoDB and no
AWS dependency. This requires **OpenTofu >= 1.10**, which is why each stack pins
`required_version = ">= 1.10"`; an older binary would silently run unlocked.

### why this works on Vultr

Vultr Object Storage (Ceph RGW) honors S3 conditional writes — verified
empirically (a conflicting `If-None-Match: *` PUT returns HTTP 412). This
contradicts some older Vultr docs that claim no locking support. To re-validate
(e.g. if behavior ever regresses), run the probe:

```bash
mise x -- uv run terraform/scripts/probe-conditional-writes.py
```

Exit `0` = locking works, exit `1` = conditional writes not honored. The probe
writes and deletes a throwaway object; it never touches real state.

### CI deploy serialization (defense in depth)

Each `deploy-*` job in `.github/workflows/cicd.yaml` has a per-stack GitHub
Actions `concurrency` group with `cancel-in-progress: false`. Two pushes to
`main` that touch the same stack queue rather than racing `tofu apply`, and an
in-flight apply is never cancelled. Distinct stacks still deploy in parallel.

### operational notes

- Applies normally run through CI on push to `main` (GitOps). Local `tofu apply`
  is also safe — `use_lockfile` locking serializes writes, so a local apply and a
  CI apply cannot corrupt state by racing (one waits on the lock).
- If a run dies mid-apply and leaves a stale lock, clear it with
  `tofu force-unlock <LOCK_ID>` (the `LOCK_ID` is printed in the
  "Error acquiring the state lock" message), only after confirming no apply is
  actually running. This removes the `<key>.tflock` object.
