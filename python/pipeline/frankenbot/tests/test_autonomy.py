"""Unit tests for :mod:`frankenbot.autonomy`.

These are the durable spec for the (dormant) autonomy policy: the ``decide``
action matrix, and the executor's hard refusal to act unless explicitly armed.
Classifications are produced by the real :func:`frankenbot.classifier.classify`
(from ``tofu show -json``-shaped plans) rather than hand-built, so the policy is
tested against genuine verdicts.
"""

from __future__ import annotations

from typing import Any

import pytest

from frankenbot.autonomy import (
    AUTONOMY_ENABLED_ENV,
    Action,
    Health,
    decide,
    execute,
    probe_health,
)
from frankenbot.classifier import Classification, Tier, classify


def _plan(*action_lists_with_types: tuple[list[str], str]) -> dict[str, Any]:
    return {
        "resource_changes": [
            {"type": rtype, "change": {"actions": actions}}
            for actions, rtype in action_lists_with_types
        ]
    }


def _eligible() -> Classification:
    """A reversible, auto-eligible T1 change (allowlisted infra minor bump)."""
    c = classify(
        _plan((["update"], "helm_release")),
        update_type="minor",
        changed_paths=["terraform/applications/foo/main.tf"],
    )
    assert c.tier is Tier.T1 and c.auto_eligible and c.reversible
    return c


def _not_eligible() -> Classification:
    """An irreversible T4 change (a destroy): never auto-mergeable."""
    c = classify(_plan((["delete"], "vultr_instance")))
    assert c.tier is Tier.T4 and not c.auto_eligible and not c.reversible
    return c


# --- decide() matrix --------------------------------------------------------


def test_not_eligible_holds() -> None:
    action = decide(
        _not_eligible(), ci_green=True, ttl_elapsed=True, health=Health.HEALTHY
    )
    assert action is Action.HOLD


def test_eligible_green_ttl_healthy_merges() -> None:
    action = decide(_eligible(), ci_green=True, ttl_elapsed=True, health=Health.HEALTHY)
    assert action is Action.MERGE


def test_degraded_in_bake_window_reverts() -> None:
    # Reversible T0..T2 + degraded => roll back, even before the TTL elapses.
    action = decide(
        _eligible(), ci_green=True, ttl_elapsed=False, health=Health.DEGRADED
    )
    assert action is Action.REVERT


def test_unknown_health_pages() -> None:
    # A monitoring blackout must never merge or revert blind.
    action = decide(_eligible(), ci_green=True, ttl_elapsed=True, health=Health.UNKNOWN)
    assert action is Action.PAGE


def test_ci_red_holds() -> None:
    action = decide(
        _eligible(), ci_green=False, ttl_elapsed=True, health=Health.HEALTHY
    )
    assert action is Action.HOLD


def test_degraded_irreversible_pages_not_reverts() -> None:
    # An irreversible/high-tier degradation can't be safely auto-rolled-back.
    action = decide(
        _not_eligible(), ci_green=True, ttl_elapsed=False, health=Health.DEGRADED
    )
    assert action is Action.PAGE


def test_healthy_not_yet_ttl_holds() -> None:
    action = decide(
        _eligible(), ci_green=True, ttl_elapsed=False, health=Health.HEALTHY
    )
    assert action is Action.HOLD


# --- execute(): dormant by default, fails loud when armed -------------------


def test_execute_is_dormant_by_default(monkeypatch: Any) -> None:
    monkeypatch.delenv(AUTONOMY_ENABLED_ENV, raising=False)
    # No side effect, no exception; returns False for a real action.
    assert execute(Action.MERGE, repo="o/r", pr=1) is False
    assert execute(Action.REVERT, repo="o/r", pr=1) is False


def test_execute_hold_is_always_noop(monkeypatch: Any) -> None:
    # HOLD short-circuits regardless of the arming flag.
    monkeypatch.setenv(AUTONOMY_ENABLED_ENV, "true")
    assert execute(Action.HOLD) is False


def test_execute_armed_fails_loud(monkeypatch: Any) -> None:
    monkeypatch.setenv(AUTONOMY_ENABLED_ENV, "true")
    with pytest.raises(NotImplementedError):
        execute(Action.MERGE, repo="o/r", pr=1)


def test_execute_requires_exact_true(monkeypatch: Any) -> None:
    # Fail-closed: anything other than exactly "true" leaves it dormant.
    monkeypatch.setenv(AUTONOMY_ENABLED_ENV, "TRUE")
    assert execute(Action.MERGE) is False


def test_probe_health_is_unknown_stub() -> None:
    assert probe_health(repo="o/r", pr=1) is Health.UNKNOWN
