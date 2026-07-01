"""Unit tests for :mod:`frankenbot.backlog`.

Two concerns:

- :class:`WorkItem` is the canonical schema — construction, defaults, enum
  coercion, and required-field validation are the durable spec.
- The three backlog adapters are SCHEMA-ONLY stubs: every ``fetch()`` must fail
  loud with ``NotImplementedError`` (never silently return ``[]``) until Phase 5
  wires them.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from frankenbot.backlog import (
    BacklogSource,
    GitHubIssuesSource,
    TodoistSource,
    TodoTxtSource,
    WorkItem,
    WorkItemKind,
    WorkItemSource,
    WorkItemStatus,
    WorkItemTier,
)


def test_workitem_minimal_defaults() -> None:
    item = WorkItem(
        id="renovate/github-actions",
        source=WorkItemSource.RENOVATE,
        kind=WorkItemKind.DEP_BUMP,
        title="Bump actions/checkout",
    )
    # Identity fields set; risk/triage fields default to their empty/None state.
    assert item.source is WorkItemSource.RENOVATE
    assert item.kind is WorkItemKind.DEP_BUMP
    assert item.status is WorkItemStatus.DETECTED
    assert item.tier is None
    assert item.semver_delta is None
    assert item.reversible is None
    assert item.pr_ref is None
    assert item.paths == []
    assert item.audit == {}


def test_workitem_full_roundtrip() -> None:
    item = WorkItem(
        id="gh/123",
        source=WorkItemSource.GITHUB_ISSUE,
        kind=WorkItemKind.MIGRATION,
        title="Migrate to v2 API",
        surface="terraform",
        tier=WorkItemTier.T3,
        semver_delta="major",
        paths=["terraform/main.tf"],
        reversible=False,
        pr_ref="dysfungi/monorepo#123",
        status=WorkItemStatus.NEEDS_HUMAN,
        audit={"detector": "renovate", "run": 42},
    )
    dumped = item.model_dump()
    # String enums serialize to their stable string values.
    assert dumped["tier"] == "T3"
    assert dumped["source"] == "github_issue"
    assert dumped["status"] == "needs_human"
    assert dumped["paths"] == ["terraform/main.tf"]


def test_workitem_coerces_enum_from_string() -> None:
    item = WorkItem(
        id="x",
        source="todoist",  # type: ignore[arg-type]
        kind="chore",  # type: ignore[arg-type]
        title="tidy",
        tier="T0",  # type: ignore[arg-type]
    )
    assert item.source is WorkItemSource.TODOIST
    assert item.kind is WorkItemKind.CHORE
    assert item.tier is WorkItemTier.T0


def test_workitem_rejects_unknown_enum_value() -> None:
    with pytest.raises(ValidationError):
        WorkItem(
            id="x",
            source="jira",  # type: ignore[arg-type]
            kind=WorkItemKind.BUG,
            title="nope",
        )


def test_workitem_requires_identity_fields() -> None:
    with pytest.raises(ValidationError):
        WorkItem(id="x", source=WorkItemSource.RENOVATE)  # type: ignore[call-arg]


@pytest.mark.parametrize(
    "source_cls, expected",
    [
        (GitHubIssuesSource, WorkItemSource.GITHUB_ISSUE),
        (TodoTxtSource, WorkItemSource.TODO_TXT),
        (TodoistSource, WorkItemSource.TODOIST),
    ],
)
def test_adapter_stubs_fetch_raise_not_implemented(
    source_cls: type[BacklogSource], expected: WorkItemSource
) -> None:
    adapter = source_cls()
    assert adapter.source is expected
    assert isinstance(adapter, BacklogSource)
    with pytest.raises(NotImplementedError):
        adapter.fetch()


def test_backlog_source_is_abstract() -> None:
    # The interface itself cannot be instantiated (guards against a no-op source).
    with pytest.raises(TypeError):
        BacklogSource()  # type: ignore[abstract]
