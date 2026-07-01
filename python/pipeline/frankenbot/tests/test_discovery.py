"""Unit tests for :mod:`frankenbot.discovery` — no network, no httpx mocking lib.

Covered:

- ``extract_slugs``: pure slug parsing (``full_name``, owner+name fallback,
  malformed skip, first-seen dedup).
- ``_collect_installation_repositories``: the pagination loop, driven by a simple
  fake client that returns fake responses (multi-page, short-page stop, empty).
- ``effective_repos``: the config integration seam — explicit vs. auto mode and
  the fail-soft fallback when discovery raises.
"""

from __future__ import annotations

from typing import Any

from frankenbot import discovery
from frankenbot.config import DEFAULT_AUTO_SURFACES, RepoConfig, Settings


class _FakeResponse:
    """Minimal stand-in for an httpx.Response (json + raise_for_status only)."""

    def __init__(self, payload: dict[str, Any]) -> None:
        self._payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict[str, Any]:
        return self._payload


class _FakeClient:
    """Returns a queued page per ``get`` call; records the params it was asked."""

    def __init__(self, pages: list[list[dict[str, Any]]]) -> None:
        self._pages = pages
        self.calls: list[dict[str, Any]] = []

    def get(self, url: str, *, params: dict[str, Any]) -> _FakeResponse:
        self.calls.append(params)
        page = params["page"]
        repos = self._pages[page - 1] if page - 1 < len(self._pages) else []
        return _FakeResponse({"repositories": repos})


# --- extract_slugs (pure) ---------------------------------------------------


def test_extract_slugs_prefers_full_name() -> None:
    repos = [{"full_name": "dysfungi/monorepo"}, {"full_name": "octo/hello"}]
    assert discovery.extract_slugs(repos) == ["dysfungi/monorepo", "octo/hello"]


def test_extract_slugs_falls_back_to_owner_and_name() -> None:
    repos = [{"owner": {"login": "octo"}, "name": "hello"}]
    assert discovery.extract_slugs(repos) == ["octo/hello"]


def test_extract_slugs_skips_malformed() -> None:
    repos: list[dict[str, Any]] = [
        {"full_name": "no-slash-here"},
        {"owner": {}, "name": "orphan"},
        {"nothing": True},
        {"full_name": "good/one"},
    ]
    assert discovery.extract_slugs(repos) == ["good/one"]


def test_extract_slugs_dedups_first_seen() -> None:
    repos = [
        {"full_name": "a/b"},
        {"full_name": "a/b"},
        {"full_name": "c/d"},
    ]
    assert discovery.extract_slugs(repos) == ["a/b", "c/d"]


# --- pagination -------------------------------------------------------------


def test_pagination_stops_on_short_page(monkeypatch: Any) -> None:
    # Page size 2: a full page then a short page ends the loop.
    monkeypatch.setattr(discovery, "_PER_PAGE", 2)
    client = _FakeClient(
        [
            [{"full_name": "o/a"}, {"full_name": "o/b"}],  # full page -> continue
            [{"full_name": "o/c"}],  # short page -> stop
        ]
    )
    repos = discovery._collect_installation_repositories(client)
    assert discovery.extract_slugs(repos) == ["o/a", "o/b", "o/c"]
    assert [c["page"] for c in client.calls] == [1, 2]


def test_pagination_stops_on_empty_page(monkeypatch: Any) -> None:
    # A full first page followed by an empty page stops without over-fetching.
    monkeypatch.setattr(discovery, "_PER_PAGE", 2)
    client = _FakeClient(
        [
            [{"full_name": "o/a"}, {"full_name": "o/b"}],
            [],
        ]
    )
    repos = discovery._collect_installation_repositories(client)
    assert discovery.extract_slugs(repos) == ["o/a", "o/b"]
    assert [c["page"] for c in client.calls] == [1, 2]


def test_pagination_single_short_page() -> None:
    client = _FakeClient([[{"full_name": "o/a"}]])
    repos = discovery._collect_installation_repositories(client)
    assert discovery.extract_slugs(repos) == ["o/a"]
    assert [c["page"] for c in client.calls] == [1]


# --- effective_repos (config integration seam) ------------------------------


def _settings(discovery_mode: str, repos: list[RepoConfig]) -> Settings:
    return Settings(
        image="ghcr.io/x/frankenbot:test", discovery=discovery_mode, repos=repos
    )


def test_effective_repos_off_returns_explicit_only(monkeypatch: Any) -> None:
    explicit = [RepoConfig(name="dysfungi/monorepo")]
    settings = _settings("off", explicit)

    def _boom(_token: str) -> list[str]:  # must NOT be called in off mode
        raise AssertionError("discovery must not run when mode is off")

    monkeypatch.setattr(discovery, "list_installation_repos", _boom)
    assert discovery.effective_repos(settings, token="t") == explicit


def test_effective_repos_auto_merges_discovered(monkeypatch: Any) -> None:
    explicit = [RepoConfig(name="dysfungi/monorepo", surfaces=["dockerfile"])]
    settings = _settings("auto", explicit)
    monkeypatch.setattr(
        discovery,
        "list_installation_repos",
        lambda _token: ["dysfungi/monorepo", "octo/new-svc"],
    )

    result = discovery.effective_repos(settings, token="t")
    names = [r.name for r in result]
    assert names == ["dysfungi/monorepo", "octo/new-svc"]
    # Explicit entry preserved verbatim (its narrower surfaces, not the defaults).
    assert result[0].surfaces == ["dockerfile"]
    # Newly discovered repo gets the default propose-only dependency surfaces.
    assert result[1].tier == "propose-only"
    assert result[1].surfaces == DEFAULT_AUTO_SURFACES


def test_effective_repos_auto_falls_back_on_error(monkeypatch: Any) -> None:
    explicit = [RepoConfig(name="dysfungi/monorepo")]
    settings = _settings("auto", explicit)

    def _raise(_token: str) -> list[str]:
        raise RuntimeError("GitHub API down")

    monkeypatch.setattr(discovery, "list_installation_repos", _raise)
    # Fail-soft: the explicit list is returned rather than propagating the error.
    assert discovery.effective_repos(settings, token="t") == explicit
