"""Unit tests for :mod:`frankenbot.dispatch` — no live Kubernetes or GitHub.

Covered:

- ``_dispatch`` fails LOUD (``NotImplementedError``) when ``discovery=auto`` is
  configured, rather than silently scanning only the explicit list (S4).
- ``_count_active_jobs`` counts NON-TERMINAL Jobs — Pending as well as Running —
  so a burst of ticks cannot over-dispatch past the concurrency cap before pods
  become active (N1). Succeeded/failed Jobs do not count.
"""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any

import pytest

from frankenbot import dispatch
from frankenbot.config import Settings

# --- S4: discovery=auto fails loud ------------------------------------------


def test_dispatch_auto_discovery_raises_not_implemented() -> None:
    settings = Settings(image="ghcr.io/x/frankenbot:test", discovery="auto", repos=[])
    with pytest.raises(NotImplementedError, match="discovery=auto not wired"):
        dispatch._dispatch(settings)


# --- N1: count non-terminal Jobs (Pending + Running), not just active>0 -----


def _job(
    *,
    completion_time: Any = None,
    conditions: list[Any] | None = None,
    active: int | None = None,
) -> SimpleNamespace:
    status = SimpleNamespace(
        completion_time=completion_time,
        conditions=conditions,
        active=active,
    )
    return SimpleNamespace(status=status)


class _FakeBatchApi:
    """Returns a fixed Job list from ``list_namespaced_job`` (no cluster)."""

    def __init__(self, jobs: list[SimpleNamespace]) -> None:
        self._jobs = jobs

    def list_namespaced_job(self, **_kwargs: Any) -> SimpleNamespace:
        return SimpleNamespace(items=self._jobs)


def test_pending_job_counts_as_active() -> None:
    # Freshly-created Job: no completion, no conditions, no active pod yet.
    api = _FakeBatchApi([_job()])
    assert dispatch._count_active_jobs(api, "frankenbot") == 1


def test_running_job_counts_as_active() -> None:
    api = _FakeBatchApi([_job(active=1)])
    assert dispatch._count_active_jobs(api, "frankenbot") == 1


def test_succeeded_and_failed_jobs_do_not_count() -> None:
    succeeded = _job(completion_time="2026-06-30T00:00:00Z")
    failed = _job(conditions=[SimpleNamespace(type="Failed", status="True")])
    pending = _job()
    api = _FakeBatchApi([succeeded, failed, pending])
    # Only the pending Job is non-terminal.
    assert dispatch._count_active_jobs(api, "frankenbot") == 1


def test_complete_condition_is_terminal() -> None:
    complete = _job(conditions=[SimpleNamespace(type="Complete", status="True")])
    assert dispatch._job_is_terminal(complete.status) is True
    api = _FakeBatchApi([complete])
    assert dispatch._count_active_jobs(api, "frankenbot") == 0
