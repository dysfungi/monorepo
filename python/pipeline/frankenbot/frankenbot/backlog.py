"""Backlog work-item schema + source adapters (Phase 5 scaffolding, SCHEMA-ONLY).

Intent
------
Define the canonical unit of Frankenbot work — the :class:`WorkItem` — and the
adapter interface (:class:`BacklogSource`) that future phases will use to pull
work from heterogeneous backlogs (GitHub Issues, ``todo.txt``, Todoist) into that
one schema. This lets the risk-tier classifier, the plan-on-PR oracle, and the
autonomy engine reason over a single shape regardless of where the work came from.

Architecture
------------
- :class:`WorkItem` is a pydantic model matching the platform plan's schema.
- :class:`BacklogSource` is the adapter ABC with a single ``fetch()`` method.
- :class:`GitHubIssuesSource`, :class:`TodoTxtSource`, :class:`TodoistSource` are
  the concrete adapters — present here as INTERFACE-ONLY STUBS.

Design decisions
----------------
- MVP self-generates its work from Renovate PRs (the deterministic radar); NO
  backlog adapter runs in the MVP. These adapters are the seam for post-MVP
  fan-out, so each ``fetch()`` deliberately raises ``NotImplementedError`` rather
  than returning fake data — a stub that silently returns ``[]`` would be an
  invisible no-op. See the platform README + the design doc referenced there.
- The schema uses string enums so serialized WorkItems (state DB rows, PR
  comments, audit records) are human-readable and stable across versions.
"""

from __future__ import annotations

import abc
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field

# Pointer used in every stub's error so the reader lands on the design + rollout.
_STUB_MSG = "Phase 5 fan-out: not wired in MVP"


class WorkItemSource(str, Enum):
    """Where a work item originated."""

    RENOVATE = "renovate"
    GITHUB_ISSUE = "github_issue"
    TODO_TXT = "todo_txt"
    TODOIST = "todoist"


class WorkItemKind(str, Enum):
    """The nature of the work."""

    DEP_BUMP = "dep_bump"
    BUG = "bug"
    CHORE = "chore"
    MIGRATION = "migration"


class WorkItemTier(str, Enum):
    """Risk tier (mirrors the classifier's T0..T4; string-valued for storage)."""

    T0 = "T0"  # docs/format-only
    T1 = "T1"  # reversible dep/config/infra
    T2 = "T2"  # reversible + codemod
    T3 = "T3"  # major / human-required
    T4 = "T4"  # irreversible / human-required


class WorkItemStatus(str, Enum):
    """Lifecycle state of a work item as it moves through the platform."""

    DETECTED = "detected"
    PROPOSED = "proposed"
    TRIAGING = "triaging"
    NEEDS_HUMAN = "needs_human"
    MERGED = "merged"
    REVERTED = "reverted"


class WorkItem(BaseModel):
    """One unit of dependency-currency / maintenance work, source-agnostic.

    Required identity fields (``id``, ``source``, ``kind``, ``title``) are always
    present; the risk/triage fields (``tier``, ``semver_delta``, ``reversible``,
    ``pr_ref``) are populated as the item moves through classification and triage.
    """

    id: str = Field(..., description="Stable unique id (source-scoped).")
    source: WorkItemSource = Field(..., description="Originating backlog source.")
    kind: WorkItemKind = Field(..., description="Nature of the work.")
    title: str = Field(..., description="Human-readable summary.")

    surface: str | None = Field(
        default=None,
        description="Dependency surface (e.g. github-actions, terraform), if any.",
    )
    tier: WorkItemTier | None = Field(
        default=None, description="Risk tier once classified (T0..T4)."
    )
    semver_delta: str | None = Field(
        default=None, description="Renovate semver delta (major/minor/patch/…)."
    )
    paths: list[str] = Field(
        default_factory=list, description="Changed/affected file paths."
    )
    reversible: bool | None = Field(
        default=None, description="Whether the change is safely revertible."
    )
    pr_ref: str | None = Field(
        default=None, description="Associated PR reference (OWNER/NAME#N or URL)."
    )
    status: WorkItemStatus = Field(
        default=WorkItemStatus.DETECTED, description="Lifecycle state."
    )
    audit: dict[str, Any] = Field(
        default_factory=dict, description="Free-form audit/provenance metadata."
    )


class BacklogSource(abc.ABC):
    """Adapter interface: pull work from a backlog into :class:`WorkItem`s."""

    #: Which source this adapter yields (set by concrete subclasses).
    source: WorkItemSource

    @abc.abstractmethod
    def fetch(self) -> list[WorkItem]:
        """Return the current open work items from this backlog source."""
        raise NotImplementedError


class GitHubIssuesSource(BacklogSource):
    """STUB — map open GitHub Issues (label-scoped) to WorkItems.

    Design: query issues via the App-installation client (see
    ``frankenbot.githubapp``), filter by a frankenbot label, and map each to a
    ``WorkItem(source=github_issue, kind=bug|chore, …)``. Not wired in MVP.
    """

    source = WorkItemSource.GITHUB_ISSUE

    def fetch(self) -> list[WorkItem]:
        raise NotImplementedError(_STUB_MSG)


class TodoTxtSource(BacklogSource):
    """STUB — parse a ``todo.txt`` file into WorkItems.

    Design: read the repo ``todo.txt`` (todo-txt format), map priority/project
    tags to ``tier``/``surface``, and emit ``WorkItem(source=todo_txt, …)``.
    Not wired in MVP.
    """

    source = WorkItemSource.TODO_TXT

    def fetch(self) -> list[WorkItem]:
        raise NotImplementedError(_STUB_MSG)


class TodoistSource(BacklogSource):
    """STUB — pull tasks from the Todoist API into WorkItems.

    Design: fetch tasks from a designated Todoist project via its REST API and
    map each to ``WorkItem(source=todoist, …)``. Not wired in MVP.
    """

    source = WorkItemSource.TODOIST

    def fetch(self) -> list[WorkItem]:
        raise NotImplementedError(_STUB_MSG)
