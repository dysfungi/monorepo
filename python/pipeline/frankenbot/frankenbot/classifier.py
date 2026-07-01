"""Reversibility / risk-tier classifier for Frankenbot changes.

Intent
------
Decide, for a single proposed change (typically a Renovate dependency bump plus
whatever the triage agent did to make CI green), *how risky it is to merge* and
*whether a machine is allowed to merge it*. The output is the reversibility
ORACLE that a future TTL auto-merge job will consult. In the MVP that auto-merge
path is DORMANT (Frankenbot is propose-only); this module exists so the policy
is written down, unit-tested, and callable from CI before we ever wire it to a
merge button.

The model
---------
Every change is mapped to a tier ``T0``..``T4`` (higher = riskier), a
``reversible`` flag, an ``auto_eligible`` flag, a ``merge_policy`` of ``auto`` or
``human``, an optional TTL (soak time in hours before auto-merge), and a list of
human-readable ``reasons``. Independent risk signals are combined
**worst-tier-wins**: the final tier is the maximum tier any signal argues for.

Primary input — a parsed OpenTofu plan (``tofu show -json``)
    We read ``resource_changes[].change.actions``. A change is **irreversible**
    if ANY resource is destroyed (``actions`` contains ``"delete"``) — this also
    covers *replace* (``["delete","create"]`` / ``["create","delete"]``, which
    both contain ``"delete"``). A plan whose actions are only among
    ``create`` / ``update`` (in-place) / ``no-op`` / ``read`` is reversible.

Secondary inputs (optional)
    ``update_type``  — Renovate semver delta (major/minor/patch/digest/pin).
    ``needs_codemod``— whether the triage agent had to migrate code.
    ``changed_paths``— the PR's changed file paths (drives path-based signals).

Tier rules (worst wins)
    T4 irreversible/human : destroy or replace in the plan, OR a DB-migration
                            path, OR a (heuristic) secret-rotation / registry-
                            publish path. No TTL.
    T3 human              : major semver bump (or a codemod on a major change).
                            No TTL.
    T2 auto (post-MVP)    : reversible change that required a codemod. TTL 72h.
    T1 auto               : reversible dependency/config/infra change, no
                            codemod. TTL 48h.
    INFRA allowlist gate  : applies to BOTH auto infra tiers (T1 and T2). A change
                            "has infra" when the plan contains resource changes OR
                            a changed path lives under a known infra directory
                            (``terraform``/``tofu``/``infra``/``live``) — so a
                            renamed stack cannot dodge the gate. Every changed
                            resource type must be on ``INFRA_AUTOMERGE_ALLOWLIST``
                            or ``auto_eligible`` is flipped off (the tier is
                            unchanged).
    T0 auto              : docs / lint / format-only change with a non-
                            destructive plan. TTL 24h.

Design decisions
----------------
- Pure & dependency-free: stdlib only (dataclasses/enum/json). Trivially unit
  testable and safe to import from any context.
- Fail loud on *malformed* input (a resource_change that is not shaped like a
  tofu plan), but NEVER raise on a well-formed-but-empty plan — an empty plan is
  simply "no infra change", hence reversible.
- Conservative by default: when we cannot verify an infra change against the
  allowlist, we withhold auto-eligibility rather than granting it.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Any, Literal

MergePolicy = Literal["auto", "human"]

# Renovate semver deltas we understand. Any other non-None value is malformed.
VALID_UPDATE_TYPES = frozenset({"major", "minor", "patch", "digest", "pin"})

# ---------------------------------------------------------------------------
# The infra auto-merge allowlist — THE real safety gate for T1 infra changes.
#
# Entries are OpenTofu resource-type *prefixes*. A reversible infra change is
# only auto-eligible if every resource it creates/updates matches one of these.
# This list is intentionally TINY and conservative; expand it deliberately, one
# well-understood resource type at a time. Everything not listed requires a
# human, even for an otherwise-reversible in-place update.
#
# Seeded with two low-blast-radius examples:
#   - helm_release : Helm chart *version* bumps (chart digest/version only).
#   - docker_image : image tag/digest pulls.
# ---------------------------------------------------------------------------
INFRA_AUTOMERGE_ALLOWLIST: frozenset[str] = frozenset(
    {
        "helm_release",
        "docker_image",
    }
)

# Path-signal building blocks. Kept small and commented — these encode policy.
_DOCS_SUFFIXES = frozenset({".md", ".markdown", ".txt", ".rst", ".adoc"})
_FORMAT_CONFIG_BASENAMES = frozenset(
    {
        ".editorconfig",
        ".prettierrc",
        ".prettierrc.json",
        ".prettierrc.yaml",
        ".prettierrc.yml",
        ".prettierignore",
        ".gitattributes",
    }
)

# tofu actions that represent a real change to a resource (used for allowlisting).
_CHANGING_ACTIONS = frozenset({"create", "update", "delete"})

# Path segments that signal an infrastructure change. Kept broad on purpose: a
# stack living under any of these MUST NOT dodge the infra allowlist gate just
# because it does not use the literal ``terraform`` directory name. This is only
# ONE of two "has infra" signals — the other is the plan actually containing
# resource changes (see ``_has_infra`` below), so a bare plan with resource
# changes is gated even when no path signal is present.
_INFRA_PATH_SEGMENTS = frozenset({"terraform", "tofu", "infra", "live"})


class Tier(IntEnum):
    """Risk tier, ordered so ``max()`` implements worst-tier-wins."""

    T0 = 0  # docs/format-only
    T1 = 1  # reversible dep/config/infra
    T2 = 2  # reversible + codemod
    T3 = 3  # major / human-required
    T4 = 4  # irreversible / human-required

    @property
    def label(self) -> str:
        """Return the canonical ``"T<n>"`` label used in serialized output."""
        return f"T{self.value}"


# TTL (soak hours) per tier. None = no TTL (auto-merge never applies).
_TIER_TTL: dict[Tier, int | None] = {
    Tier.T0: 24,
    Tier.T1: 48,
    Tier.T2: 72,
    Tier.T3: None,
    Tier.T4: None,
}

_AUTO_TIERS = frozenset({Tier.T0, Tier.T1, Tier.T2})


@dataclass(frozen=True)
class Classification:
    """The immutable verdict for one change.

    Attributes
    ----------
    tier:
        The worst-wins risk tier.
    reversible:
        True unless the plan destroys or replaces a resource.
    auto_eligible:
        True when a machine is permitted to merge this change (an auto tier that
        also cleared the infra allowlist gate). Auto-merge itself is dormant in
        the MVP; this flag is what will ungate it later.
    merge_policy:
        ``"auto"`` iff ``auto_eligible`` else ``"human"``.
    ttl_hours:
        Soak time before auto-merge, or None when auto-merge does not apply.
    allowlisted:
        Whether the change cleared the infra auto-merge allowlist gate. Vacuously
        True when there are no in-scope infra resource changes to gate.
    reasons:
        Human-readable justifications, ordered base-signal first.
    """

    tier: Tier
    reversible: bool
    auto_eligible: bool
    merge_policy: MergePolicy
    ttl_hours: int | None
    allowlisted: bool
    reasons: list[str]

    def to_dict(self) -> dict[str, Any]:
        """Return a JSON-serializable dict (tier rendered as its ``T<n>`` label)."""
        return {
            "tier": self.tier.label,
            "reversible": self.reversible,
            "auto_eligible": self.auto_eligible,
            "merge_policy": self.merge_policy,
            "ttl_hours": self.ttl_hours,
            "allowlisted": self.allowlisted,
            "reasons": list(self.reasons),
        }

    def to_comment(self) -> str:
        """Render a compact Markdown block suitable for a PR comment."""
        ttl = f"{self.ttl_hours}h" if self.ttl_hours is not None else "n/a"
        policy = "auto" if self.merge_policy == "auto" else "human"
        eligible = "yes" if self.auto_eligible else "no"
        lines = [
            "### Frankenbot risk classification",
            f"- **Tier:** {self.tier.label}",
            f"- **Reversible:** {'yes' if self.reversible else 'no'}",
            f"- **Merge policy:** {policy} (auto-eligible: {eligible})",
            f"- **TTL:** {ttl}",
            "- **Reasons:**",
        ]
        lines.extend(f"  - {reason}" for reason in self.reasons)
        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Plan parsing helpers (fail loud on malformed shapes; tolerant of empties).
# ---------------------------------------------------------------------------
def _resource_changes(plan: dict[str, Any]) -> list[Any]:
    """Return the ``resource_changes`` list, or [] when absent.

    Raises ValueError if present but not a list (malformed plan).
    """
    rcs = plan.get("resource_changes")
    if rcs is None:
        return []
    if not isinstance(rcs, list):
        raise ValueError("plan 'resource_changes' must be a list")
    return rcs


def _actions_of(resource_change: Any) -> list[str]:
    """Return the action list for one ``resource_change``.

    Fails loud if the resource_change is not shaped like a tofu plan entry.
    """
    if not isinstance(resource_change, dict):
        raise ValueError("each resource_change must be a JSON object")
    change = resource_change.get("change")
    if change is None:
        return []
    if not isinstance(change, dict):
        raise ValueError("resource_change.change must be a JSON object")
    actions = change.get("actions")
    if actions is None:
        return []
    if not isinstance(actions, list) or not all(isinstance(a, str) for a in actions):
        raise ValueError("resource_change.change.actions must be a list of strings")
    return actions


def _plan_is_irreversible(plan: dict[str, Any]) -> bool:
    """A plan is irreversible if ANY resource is destroyed (delete/replace)."""
    return any("delete" in _actions_of(rc) for rc in _resource_changes(plan))


def _changed_resource_types(plan: dict[str, Any]) -> set[str]:
    """Return the tofu resource types that are actually being changed."""
    types: set[str] = set()
    for resource_change in _resource_changes(plan):
        if _CHANGING_ACTIONS.intersection(_actions_of(resource_change)):
            rtype = resource_change.get("type")
            if isinstance(rtype, str) and rtype:
                types.add(rtype)
    return types


# ---------------------------------------------------------------------------
# Path signal helpers.
# ---------------------------------------------------------------------------
def _segments(path: str) -> list[str]:
    """Split a path into non-empty segments (POSIX or Windows separators)."""
    return [s for s in path.replace("\\", "/").split("/") if s]


def _has_segment(path: str, segment: str) -> bool:
    return segment in _segments(path)


def _is_docs_or_format(path: str) -> bool:
    """True if the path is documentation or a formatting/config-only file."""
    name = _segments(path)[-1] if _segments(path) else path
    suffix = ("." + name.rsplit(".", 1)[-1].lower()) if "." in name else ""
    if suffix in _DOCS_SUFFIXES:
        return True
    return name in _FORMAT_CONFIG_BASENAMES


def _is_migration(path: str) -> bool:
    """True for DB migration files (a ``migrations`` path segment)."""
    return _has_segment(path, "migrations")


def _looks_like_secret_rotation(path: str) -> bool:
    """Heuristic: a path that both mentions a secret and a rotation.

    Deliberately narrow (requires BOTH tokens) to avoid flagging every file that
    merely lives near secrets. This is a best-effort T4 signal, not a guarantee.
    """
    low = path.lower()
    return "secret" in low and "rotat" in low


def _looks_like_registry_publish(path: str) -> bool:
    """Heuristic: a GitHub Actions workflow that publishes/releases artifacts."""
    segs = [s.lower() for s in _segments(path)]
    if ".github" not in segs or "workflows" not in segs:
        return False
    return "publish" in segs[-1] or "release" in segs[-1]


def _on_allowlist(resource_type: str) -> bool:
    """True if ``resource_type`` matches an allowlist prefix."""
    return any(
        resource_type == entry or resource_type.startswith(entry)
        for entry in INFRA_AUTOMERGE_ALLOWLIST
    )


def _has_infra(plan: dict[str, Any], paths: list[str]) -> bool:
    """True if this change touches infrastructure and must clear the allowlist.

    "Has infra" is (the plan contains real resource changes) OR (a changed path
    lives under a known infra directory). Relying on the path alone was unsafe —
    a stack under ``infra/``/``tofu/``/``live/`` (or a renamed dir) could dodge
    the gate — so a plan with resource changes is enough on its own.
    """
    if _changed_resource_types(plan):
        return True
    return any(
        _has_segment(path, seg) for path in paths for seg in _INFRA_PATH_SEGMENTS
    )


# ---------------------------------------------------------------------------
# Public API.
# ---------------------------------------------------------------------------
def load_plan(path: str | Path) -> dict[str, Any]:
    """Load a ``tofu show -json`` plan from disk into a dict.

    Fails loud if the file is missing or is not a JSON object.
    """
    file_path = Path(path)
    if not file_path.is_file():
        raise FileNotFoundError(f"plan file not found: {str(path)!r}")
    data = json.loads(file_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"plan file {str(path)!r} must contain a JSON object")
    return data


def classify(
    plan: dict[str, Any],
    *,
    update_type: str | None = None,
    needs_codemod: bool = False,
    changed_paths: list[str] | None = None,
) -> Classification:
    """Classify a change into a :class:`Classification` (worst-tier-wins).

    Parameters
    ----------
    plan:
        A parsed ``tofu show -json`` document (or ``{}`` for a non-infra change).
    update_type:
        Renovate semver delta; one of ``VALID_UPDATE_TYPES`` or None.
    needs_codemod:
        Whether the triage agent had to migrate code to make CI pass.
    changed_paths:
        The PR's changed file paths (drives docs/migration/infra signals).
    """
    if update_type is not None and update_type not in VALID_UPDATE_TYPES:
        raise ValueError(
            f"update_type={update_type!r} is invalid; expected one of "
            f"{sorted(VALID_UPDATE_TYPES)} or None."
        )
    paths = list(changed_paths or [])

    irreversible = _plan_is_irreversible(plan)
    reversible = not irreversible

    # Base tier: docs/format-only floors at T0, everything else at T1.
    reasons: list[str] = []
    docs_only = bool(paths) and all(_is_docs_or_format(p) for p in paths)
    if docs_only and not irreversible:
        base_tier = Tier.T0
        reasons.append("changed paths are docs/format-only")
    else:
        base_tier = Tier.T1
        reasons.append("reversible dependency/config/infra change (default tier)")

    # Escalating signals — each argues for a tier; the max wins.
    escalations: list[tuple[Tier, str]] = []
    if irreversible:
        escalations.append(
            (Tier.T4, "tofu plan destroys or replaces resources (irreversible)")
        )
    for path in paths:
        if _is_migration(path):
            escalations.append(
                (Tier.T4, f"changed path is a database migration: {path}")
            )
        if _looks_like_secret_rotation(path):
            escalations.append(
                (Tier.T4, f"changed path looks like secret rotation: {path}")
            )
        if _looks_like_registry_publish(path):
            escalations.append(
                (Tier.T4, f"changed path looks like a registry publish/release: {path}")
            )
    if update_type == "major":
        escalations.append((Tier.T3, "major semver bump requires human review"))
    if needs_codemod and not irreversible and update_type != "major":
        escalations.append((Tier.T2, "reversible change required an agent codemod"))

    tier = max([base_tier, *(t for t, _ in escalations)])
    reasons.extend(reason for _, reason in escalations)

    # Base auto-eligibility from the tier; the infra allowlist may withdraw it.
    auto_eligible = tier in _AUTO_TIERS
    allowlisted = True
    has_infra = _has_infra(plan, paths)

    # Gate BOTH auto infra tiers (T1 and T2). A codemod'd infra change (T2) is no
    # less in need of the allowlist than a plain one (T1).
    if tier in (Tier.T1, Tier.T2) and has_infra:
        resource_types = _changed_resource_types(plan)
        if resource_types:
            offenders = sorted(t for t in resource_types if not _on_allowlist(t))
            allowlisted = not offenders
            if offenders:
                auto_eligible = False
                reasons.append(
                    "infra resource not on auto-merge allowlist: "
                    + ", ".join(offenders)
                )
        else:
            # Terraform files changed but the plan shows no resource changes we
            # can verify — withhold auto-merge rather than guess (conservative).
            allowlisted = False
            auto_eligible = False
            reasons.append(
                "infra change with no parseable plan resources; cannot verify "
                "allowlist"
            )

    merge_policy: MergePolicy = "auto" if auto_eligible else "human"

    return Classification(
        tier=tier,
        reversible=reversible,
        auto_eligible=auto_eligible,
        merge_policy=merge_policy,
        ttl_hours=_TIER_TTL[tier],
        allowlisted=allowlisted,
        reasons=reasons,
    )
