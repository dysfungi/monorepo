"""Auto-merge / rollback decision + execution engine — DORMANT by design.

Intent
------
Phase 4 wrote down the autonomy policy so it is version-controlled, unit-tested,
and callable *before* it is ever wired to a merge button. The MVP is
**propose-only**: the decision function is pure and exercised by tests, but the
executor HARD-REFUSES to take any action unless ``FRANKENBOT_AUTONOMY_ENABLED``
is exactly ``"true"`` — and nothing in this repo sets that variable. Shipping the
engine dormant lets the policy mature under review without granting a machine
merge/revert rights on day one.

The two halves
--------------
``decide(...)``  — PURE. Maps (risk classification + CI state + TTL/bake state +
    live health) to one of four actions: HOLD, MERGE, REVERT, PAGE. No I/O, no
    environment reads; total over its inputs. This is the entire policy.

``execute(...)`` — the DORMANT executor. With autonomy disabled (the default and
    only supported MVP state) it logs "autonomy dormant; would <action>" and
    returns having done nothing. With the flag flipped on it fails LOUD
    (NotImplementedError) rather than silently pretending — the live merge/revert
    integration is deliberately not built yet.

Health signal
-------------
``probe_health(...)`` is a documented STUB returning UNKNOWN. UNKNOWN is the
safe default: on a monitoring blackout the policy PAGEs a human and NEVER
auto-reverts. Wiring it to real signals (the Grafana Cloud alert plane and the
Honeycomb SLI burn trigger — see docs/ and the observability memory) is the next
step for the live dev loop.

Policy summary (see ``decide``)
-------------------------------
- health == UNKNOWN                         -> PAGE  (never act blind)
- health == DEGRADED, reversible & T0..T2   -> REVERT (roll back in the bake window)
- health == DEGRADED, otherwise             -> PAGE  (cannot safely auto-revert)
- auto_eligible & merge_policy==auto & CI green & TTL elapsed & not DEGRADED -> MERGE
- everything else                           -> HOLD
"""

from __future__ import annotations

import enum
import logging
import os

from frankenbot.classifier import Classification, Tier

log = logging.getLogger("frankenbot.autonomy")

# The env flag that would arm the executor. Intentionally set NOWHERE in this
# repo — the MVP is propose-only. Exact string "true" required (fail-closed).
AUTONOMY_ENABLED_ENV = "FRANKENBOT_AUTONOMY_ENABLED"

# Reversible auto-tiers eligible for an automated rollback during the bake window.
_REVERTIBLE_TIERS = frozenset({Tier.T0, Tier.T1, Tier.T2})


class Health(enum.Enum):
    """Live health verdict for a baking change."""

    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNKNOWN = "unknown"


class Action(enum.Enum):
    """The four terminal decisions the engine can reach."""

    HOLD = "hold"  # do nothing yet (keep waiting / propose-only)
    MERGE = "merge"  # auto-merge (dormant)
    REVERT = "revert"  # auto-roll-back a degraded reversible change (dormant)
    PAGE = "page"  # escalate to a human


def decide(
    classification: Classification,
    *,
    ci_green: bool,
    ttl_elapsed: bool,
    health: Health,
) -> Action:
    """Pure policy: choose an :class:`Action`. No side effects.

    Ordering is deliberate (guard clauses, most-conservative first):

    1. UNKNOWN health -> PAGE. We never act on a monitoring blackout.
    2. DEGRADED health -> REVERT a reversible T0..T2 change (safe to roll back);
       otherwise PAGE (an irreversible/high-tier degradation needs a human).
    3. MERGE only when the change is auto-eligible, its policy is ``auto``, CI is
       green, the TTL/bake window has elapsed, and health is not DEGRADED (health
       is HEALTHY here, DEGRADED/UNKNOWN having returned above).
    4. Otherwise HOLD.
    """
    if health is Health.UNKNOWN:
        return Action.PAGE

    if health is Health.DEGRADED:
        if classification.reversible and classification.tier in _REVERTIBLE_TIERS:
            return Action.REVERT
        return Action.PAGE

    # health is HEALTHY beyond this point.
    if (
        classification.auto_eligible
        and classification.merge_policy == "auto"
        and ci_green
        and ttl_elapsed
    ):
        return Action.MERGE

    return Action.HOLD


def _autonomy_enabled() -> bool:
    """True only when the arming flag is exactly ``"true"`` (fail-closed)."""
    return os.environ.get(AUTONOMY_ENABLED_ENV) == "true"


def execute(action: Action, *, repo: str = "", pr: int | None = None) -> bool:
    """Dormant executor. Returns True iff a side effect was performed.

    In the MVP (autonomy disabled) this NEVER performs a side effect: it logs
    what it *would* do and returns False. HOLD is always a no-op regardless. When
    the flag is armed it raises NotImplementedError — the live merge/revert/page
    integration is intentionally not built yet, and failing loud beats silently
    doing nothing under the impression that autonomy is live.
    """
    if action is Action.HOLD:
        return False

    if not _autonomy_enabled():
        log.info(
            "autonomy dormant; would %s",
            action.value,
            extra={"fb_action": action.value, "fb_repo": repo, "fb_pr": pr},
        )
        return False

    raise NotImplementedError(
        f"live autonomy executor is not implemented (action={action.value!r}); "
        "the MVP is propose-only. Unset FRANKENBOT_AUTONOMY_ENABLED."
    )


def probe_health(repo: str = "", pr: int | None = None) -> Health:
    """STUB health probe. Always returns UNKNOWN (safe: PAGE, never auto-revert).

    To make autonomy live, wire this to the real user-facing signals:
      - the Grafana Cloud free-tier alert plane (burn-rate / deadman rules), and
      - the Honeycomb SLI burn trigger.
    Until then UNKNOWN keeps the engine conservative — a monitoring blackout must
    never look HEALTHY.
    """
    return Health.UNKNOWN
