"""Postgres state DAL for Frankenbot (work_state + budget_daily).

Intent
------
Give the dispatcher durable, cross-run memory so it does not re-triage identical
content on every 30-minute tick, and a place to accumulate/consult a daily spend
budget. Backed by the ``frankenbot`` database on the shared Vultr managed
Postgres (provisioned in terraform/applications/frankenbot).

Architecture
------------
- The connection string comes from ``DATABASE_URL`` (a k8s Secret env in prod:
  ``frankenbot-db``). It is read **lazily** — importing this module never touches
  the environment or the network, so pure helpers (``fingerprint``) and the unit
  tests work with no database present. Any DB-touching function fails loud if
  ``DATABASE_URL`` is missing.
- One short-lived connection per call. The dispatcher is a batch CronJob (a
  handful of queries per tick), so a pool would be wasted complexity; psycopg's
  connection context manager commits on clean exit.

Design decisions
----------------
- ``fingerprint`` is a PURE, DB-free helper: a stable content hash over the
  dedup-relevant fields. Order-INDEPENDENT for unordered collections (sets), and
  order-PRESERVING for sequences (lists/tuples) — because in some fields order is
  meaningful and in others it is not. This is unit-tested without a database.
- Upserts (``ON CONFLICT``) make ``record_run`` / ``add_budget`` idempotent and
  safe under the dispatcher's ``concurrency_policy: Forbid`` (no two ticks run at
  once, but a retried tick must not double-count).
"""

from __future__ import annotations

import hashlib
import json
import os
from collections.abc import Mapping
from typing import Any

import psycopg

# ---------------------------------------------------------------------------
# Pure helper: fingerprint (no DB, no env — trivially unit-testable).
# ---------------------------------------------------------------------------


def _canonical(value: Any) -> Any:
    """Return an order-normalized, JSON-serializable view of ``value``.

    Mappings and sequences recurse. Sets/frozensets are rendered order-
    independently (sorted by the stable serialization of their elements) because
    a *set* of, e.g., changed paths has no meaningful order. Lists/tuples keep
    their order — the caller chose a sequence precisely when order matters.
    """
    if isinstance(value, Mapping):
        # json.dumps(sort_keys=True) later normalizes key order for mappings.
        return {str(k): _canonical(v) for k, v in value.items()}
    if isinstance(value, (set, frozenset)):
        return {
            "__set__": sorted(
                json.dumps(_canonical(v), sort_keys=True, default=str) for v in value
            )
        }
    if isinstance(value, (list, tuple)):
        return [_canonical(v) for v in value]
    return value


def fingerprint(*args: Any, **fields: Any) -> str:
    """Stable content hash of the dedup-relevant fields.

    Positional ``args`` are ordered; keyword ``fields`` are order-independent
    (keys are sorted). Unordered collections passed as values hash independent of
    element order; sequences do not. Returns a hex sha256 digest.
    """
    payload = {
        "args": [_canonical(a) for a in args],
        "fields": {k: _canonical(v) for k, v in fields.items()},
    }
    blob = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# DB access (lazy DSN; fail loud when absent).
# ---------------------------------------------------------------------------


def _dsn() -> str:
    """Return ``DATABASE_URL`` or fail loud.

    Called only by DB-touching functions, so a missing URL surfaces exactly when
    the database is actually needed (not at import time).
    """
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        raise RuntimeError(
            "DATABASE_URL is not set; the Postgres state DAL requires it. In "
            "cluster it is provided by the frankenbot-db Secret (dispatcher only)."
        )
    return dsn


def record_run(
    repo: str,
    surface: str,
    pr: int | None,
    status: str,
    fingerprint: str,
    ttl_hours: int | None,
) -> None:
    """Upsert the work_state row for ``(repo, surface)`` (idempotent).

    The ``ON CONFLICT`` upsert takes a row lock on the existing PK row, so
    concurrent/retried writers converge rather than duplicate.
    """
    with psycopg.connect(_dsn()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO work_state
                    (repo, surface, last_run, last_pr, status,
                     fingerprint, ttl_hours, updated_at)
                VALUES (%s, %s, now(), %s, %s, %s, %s, now())
                ON CONFLICT (repo, surface) DO UPDATE SET
                    last_run    = now(),
                    last_pr     = EXCLUDED.last_pr,
                    status      = EXCLUDED.status,
                    fingerprint = EXCLUDED.fingerprint,
                    ttl_hours   = EXCLUDED.ttl_hours,
                    updated_at  = now()
                """,
                (repo, surface, pr, status, fingerprint, ttl_hours),
            )


def already_done(repo: str, surface: str, fingerprint: str) -> bool:
    """Return True if this exact content was already handled (cross-run dedup).

    A prior row for ``(repo, surface)`` with the same fingerprint that is not in
    a ``failed`` state means we already dispatched/completed this content — skip
    it. A ``failed`` row is allowed to be retried.
    """
    with psycopg.connect(_dsn()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT 1 FROM work_state
                WHERE repo = %s AND surface = %s AND fingerprint = %s
                  AND status IS DISTINCT FROM 'failed'
                LIMIT 1
                """,
                (repo, surface, fingerprint),
            )
            return cur.fetchone() is not None


def add_budget(tokens: int, cents: int) -> None:
    """Add ``tokens``/``cents`` to today's (UTC) budget accumulator (upsert)."""
    with psycopg.connect(_dsn()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO budget_daily (day, tokens_used, spend_cents)
                VALUES (CURRENT_DATE, %s, %s)
                ON CONFLICT (day) DO UPDATE SET
                    tokens_used = budget_daily.tokens_used + EXCLUDED.tokens_used,
                    spend_cents = budget_daily.spend_cents + EXCLUDED.spend_cents
                """,
                (tokens, cents),
            )


def budget_today() -> tuple[int, int]:
    """Return ``(tokens_used, spend_cents)`` for today (UTC); ``(0, 0)`` if none."""
    with psycopg.connect(_dsn()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT tokens_used, spend_cents FROM budget_daily "
                "WHERE day = CURRENT_DATE"
            )
            row = cur.fetchone()
            if row is None:
                return (0, 0)
            return (int(row[0]), int(row[1]))
