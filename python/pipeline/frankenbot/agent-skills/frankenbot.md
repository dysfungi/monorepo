# Skill: Frankenbot auto-merge exception

Frankenbot is the one deliberate exception to the standard
"never auto-merge" rule: the **deployed runtime agent** is permitted to advance
dependency PRs autonomously as the platform matures.

## What that means today (MVP)

- The override is **DORMANT.** MVP is **propose-only**: the agent pushes at most
  one fix commit to an existing PR branch and never merges.
- Merges in MVP are performed by **humans**.

## What changes later

- **Auto-merge for low-risk tiers (T0–T2)** arrives in **Phase 4**, gated by
  risk tier and green CI. Until then, treat any instinct to merge as out of
  scope and stop at "propose".

## Scope guard

This exception applies ONLY to the deployed Frankenbot runtime agent. It does not
authorize merging in any other context.
