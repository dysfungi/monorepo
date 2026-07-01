"""Unit tests for :mod:`frankenbot.state`.

Two concerns, both DB-free:

- ``fingerprint`` is a pure content hash: stable, order-independent for unordered
  collections (sets), order-preserving for sequences (lists/tuples), and
  sensitive to positional-argument order and value changes.
- The DB-touching functions fail LOUD when ``DATABASE_URL`` is absent (the DSN is
  read lazily), so they are safe to import and call in a test with no database —
  the call raises before any connection is attempted.
"""

from __future__ import annotations

from typing import Any

import pytest

from frankenbot.state import already_done, fingerprint, record_run


def test_fingerprint_is_stable() -> None:
    a = fingerprint(repo="o/r", surface="renovate/dep", sha="abc")
    b = fingerprint(repo="o/r", surface="renovate/dep", sha="abc")
    assert a == b


def test_fingerprint_is_hex_sha256() -> None:
    fp = fingerprint(repo="o/r")
    assert len(fp) == 64
    assert all(c in "0123456789abcdef" for c in fp)


def test_fingerprint_keyword_order_independent() -> None:
    # Keyword fields hash independent of the order they are passed in.
    a = fingerprint(repo="o/r", surface="s", sha="x")
    b = fingerprint(sha="x", surface="s", repo="o/r")
    assert a == b


def test_fingerprint_sets_are_order_independent() -> None:
    a = fingerprint(paths={"a", "b", "c"})
    b = fingerprint(paths={"c", "a", "b"})
    assert a == b


def test_fingerprint_lists_are_order_preserving() -> None:
    # A sequence encodes intended order — different order => different fingerprint.
    a = fingerprint(seq=["a", "b"])
    b = fingerprint(seq=["b", "a"])
    assert a != b


def test_fingerprint_positional_order_matters() -> None:
    assert fingerprint("a", "b") != fingerprint("b", "a")


def test_fingerprint_value_change_differs() -> None:
    assert fingerprint(sha="x") != fingerprint(sha="y")


def test_fingerprint_nested_dict_key_order_independent() -> None:
    a = fingerprint(meta={"k1": 1, "k2": 2})
    b = fingerprint(meta={"k2": 2, "k1": 1})
    assert a == b


# --- DB functions fail loud without DATABASE_URL (no live DB required) -------


def test_already_done_requires_database_url(monkeypatch: Any) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with pytest.raises(RuntimeError):
        already_done("o/r", "surface", "deadbeef")


def test_record_run_requires_database_url(monkeypatch: Any) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with pytest.raises(RuntimeError):
        record_run("o/r", "surface", 1, "dispatched", "deadbeef", None)
