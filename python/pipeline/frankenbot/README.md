# 🧟 Frankenbot

An **in-cluster, agentic dependency-currency platform**. Renovate is the
deterministic radar; a fleet of ephemeral Claude agents does the reasoning
(changelog analysis, risk tiering, migration) on top of every PR it raises.

- **MVP (today): this repo only, strictly PROPOSE-ONLY.** Nothing auto-merges;
  humans merge. The autonomy engine ships **dormant**.
- **Post-MVP (Phase 5, scaffolded): multi-repo fan-out** — broadened Renovate
  surfaces, App-installation repo discovery, and pluggable backlog sources.

## Architecture

```
Renovate radar (.github/workflows/renovate.yaml + renovate.json5)
      │  detects updates, opens propose-only PRs (label: frankenbot)
      ▼
CI (GitHub Actions)  ── PR CI goes RED ──►  needs triage
      ▼
in-cluster CronJob dispatcher (frankenbot dispatch)
      │  finds RED, un-triaged frankenbot PRs; concurrency-gated
      ▼
ephemeral triage Job per PR (frankenbot triage)  ── one per PR, isolated ──►
      │  reads failing logs, attempts ≤1 fix commit, else posts triage comment
      ▼
PR updated / labeled  ──►  human review + merge (MVP)
```

- **Risk-tier classifier** (`classifier.py`): maps a `tofu show -json` plan +
  Renovate semver delta → tier **T0..T4** (reversible → irreversible).
- **Plan-on-PR oracle**: the classifier runs against the PR's tofu plan to judge
  reversibility before any autonomous action would be considered.
- **State**: Postgres (`state.py`) for cross-run dedup. Degrades gracefully to
  PR-label dedup when `DATABASE_URL` is absent. (A daily spend cap is a Phase-4
  follow-up — see the TODO in `state.py`.)
- **Autonomy**: `autonomy.py` decides MERGE/REVERT/HOLD/PAGE but is **DORMANT** —
  `execute()` no-ops unless explicitly armed (see the flag below).

## Phase 0 — the one manual prerequisite (USER action)

Everything else is automated; these two steps must be done by a human **before**
the platform can authenticate, and are the only manual gate to going live.

1. **Create the GitHub App** and install it on the target repo(s). Capture the
   **App ID**, **Installation ID**, and a generated **private key** (PEM).

   **GitHub App — repository permissions (least-privilege):**

   | Permission      | Level        | Why                                                                                                         |
   | --------------- | ------------ | ----------------------------------------------------------------------------------------------------------- |
   | Metadata        | Read         | mandatory baseline                                                                                          |
   | Contents        | Read & write | push branches / fix commits                                                                                 |
   | Workflows       | Read & write | edit `.github/workflows/*` (Renovate action-pin bumps) — a **dedicated** permission, separate from Contents |
   | Pull requests   | Read & write | open/update PRs + PR comments                                                                               |
   | Issues          | Read & write | PR labels + Renovate's Dependency Dashboard (a real Issue)                                                  |
   | Checks          | Read         | read CI check-runs to find failing PRs                                                                      |
   | Commit statuses | Read & write | Renovate reads/sets commit statuses                                                                         |
   | Actions         | Read & write | read = download run logs for triage; write = re-run failed workflows                                        |

   Webhooks: **off** (MVP is cron-poll). Install on this repo only for the MVP; Phase 5 fan-out reuses the same set. Trim options: Actions → Read-only if you don't want triage to re-run workflows.

2. **Create the 1Password items** (Frankenstructure vault) that ESO syncs into
   cluster Secrets:

   - `GitHub App - Frankenbot` — `app id`, `installation id`, `private key`
   - `Anthropic API Key - Frankenbot` — `credential`
   - `Postgres - Frankenbot` — `password`

   Note: the GitHub App uses installation-token auth (App ID + private key),
   NOT OAuth — so `client id`, `client secret`, and `username` are not used.

## Kill switch

Any ONE of these halts the platform:

- **ConfigMap / env**: set `enabled: false` (→ `FRANKENBOT_ENABLED=false`). The
  dispatcher exits 0 before doing any work.
- **CronJob**: `kubectl patch cronjob frankenbot-dispatch -p '{"spec":{"suspend":true}}'`.
- **Disable the GitHub App** (revoke installation) — cuts all API access.
- **ResourceQuota → 0** in the `frankenbot` namespace — blocks new triage Jobs.

## Autonomy flag

- `FRANKENBOT_AUTONOMY_ENABLED` (default **false**). Must be **exactly** `true`
  to arm auto-merge/auto-revert. **Nothing sets it in the MVP** — the autonomy
  engine is present but dormant, and even when armed it acts only on reversible,
  CI-green, health-verified changes within tier policy.

## Verification checklist

- [ ] **App auth** — `mint_installation_token()` succeeds (App ID / installation
      / PEM correct).
- [ ] **Renovate** — `renovate --dry-run` (or the workflow) opens propose-only
      PRs labeled `frankenbot`; `renovate-config-validator` passes on
      `renovate.json5`.
- [ ] **Image build** — `docker compose build` (or `mise run build`) produces the
      triage image.
- [ ] **Cluster smoke** — a manually-triggered dispatch spawns exactly one triage
      Job per RED PR, pinned to the infrastructure node pool.
- [ ] **Kill switch** — `FRANKENBOT_ENABLED=false` and CronJob `suspend` both
      stop dispatch cleanly.
- [ ] **State dedup** — a re-run does NOT re-dispatch an unchanged PR (Postgres
      fingerprint); DB-absent falls back to label dedup.
- [ ] **Classifier unit tests** — `pytest` green (classifier + autonomy + state +
      discovery + backlog).

## Layout

| Path                         | Role                                                                |
| ---------------------------- | ------------------------------------------------------------------- |
| `renovate.json5` (repo root) | Radar config — enabled surfaces, grouping, throttles (propose-only) |
| `frankenbot/dispatch.py`     | CronJob: find RED PRs, fan out triage Jobs                          |
| `frankenbot/triage.py`       | Ephemeral per-PR worker                                             |
| `frankenbot/classifier.py`   | Risk-tier (T0..T4) classifier                                       |
| `frankenbot/autonomy.py`     | MERGE/REVERT/HOLD/PAGE decision engine (dormant)                    |
| `frankenbot/state.py`        | Postgres cross-run dedup (spend cap deferred — Phase 4)             |
| `frankenbot/discovery.py`    | App-installations repo discovery (Phase 5)                          |
| `frankenbot/backlog.py`      | `WorkItem` schema + backlog adapters (Phase 5 stubs)                |
| `frankenbot/config.py`       | Typed settings + `repos.yaml` policy loading                        |
| `repos.yaml`                 | Per-repo policy + `discovery` mode                                  |
