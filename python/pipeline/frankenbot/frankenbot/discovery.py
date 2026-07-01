"""Multi-repo discovery via the GitHub App installations API (Phase 5 scaffolding).

Intent
------
Let Frankenbot learn the set of in-scope repositories *dynamically* from where its
GitHub App is installed, rather than requiring every repo to be hand-listed in
``repos.yaml``. This is the substrate for the post-MVP multi-repo fan-out.

Architecture
------------
- ``list_installation_repos(token)`` GETs ``/installation/repositories``
  (paginated) using the *installation* token and returns ``owner/name`` slugs.
  It reuses :class:`frankenbot.githubapp.GitHubClient` (its authed httpx client
  and headers) rather than building a second client.
- ``effective_repos(settings, token)`` is the integration seam: when
  ``settings.discovery == "auto"`` it uses the installations API as the source of
  truth and merges the result with any explicit ``repos.yaml`` overrides (see
  :meth:`frankenbot.config.Settings.merge_discovered`). Otherwise it returns the
  explicit list unchanged.

Design decisions
----------------
- Discovery is NOT a hard dependency. If the API call fails, ``effective_repos``
  logs the error and FALLS BACK to the explicit ``repos.yaml`` list — a dynamic
  radar outage must never take the dispatcher offline.
- The pagination + slug-parsing logic is kept as small pure-ish helpers
  (``_collect_installation_repositories`` takes any object with a ``.get``; the
  slug parser is a pure function) so both are unit-testable with a simple fake,
  no network and no httpx mocking library.
- MVP does not call this: ``repos.yaml`` ships with ``discovery`` unset (``off``)
  and ``dysfungi/monorepo`` as the single explicit entry. This module is wired
  behavior for a later phase, present now only as scaffolding.
"""

from __future__ import annotations

import logging
from typing import Any, Protocol

from frankenbot import githubapp
from frankenbot.config import RepoConfig, Settings

log = logging.getLogger("frankenbot.discovery")

# GitHub REST default max page size.
_PER_PAGE = 100

# Path for the installation-scoped repository listing (installation token).
_INSTALLATION_REPOS_PATH = "/installation/repositories"


class _SupportsGet(Protocol):
    """Minimal structural type for the httpx client method we depend on.

    Both :class:`httpx.Client` and the test fakes satisfy this, so the paginator
    needs neither the real client nor an HTTP mocking library.
    """

    def get(self, url: str, *, params: dict[str, Any]) -> Any: ...


def _extract_slug(repository: dict[str, Any]) -> str | None:
    """Return the ``owner/name`` slug for one repository object, or None.

    Prefers GitHub's ``full_name`` and falls back to composing it from the nested
    ``owner.login`` + ``name`` fields. Returns None (skipped by the caller) when
    neither yields a well-formed ``owner/name``.
    """
    full_name = repository.get("full_name")
    if isinstance(full_name, str) and full_name.count("/") == 1:
        head, tail = full_name.split("/", 1)
        if head and tail:
            return full_name

    owner_obj = repository.get("owner") or {}
    owner = owner_obj.get("login") if isinstance(owner_obj, dict) else None
    name = repository.get("name")
    if owner and name:
        return f"{owner}/{name}"
    return None


def extract_slugs(repositories: list[dict[str, Any]]) -> list[str]:
    """Map GitHub repository objects to ``owner/name`` slugs (skipping malformed).

    Pure function: deterministic, order-preserving, and deduplicated while keeping
    first-seen order.
    """
    seen: set[str] = set()
    slugs: list[str] = []
    for repo in repositories:
        slug = _extract_slug(repo)
        if slug and slug not in seen:
            seen.add(slug)
            slugs.append(slug)
    return slugs


def _collect_installation_repositories(client: _SupportsGet) -> list[dict[str, Any]]:
    """Page through ``/installation/repositories`` and return the repo objects.

    ``client`` is anything exposing httpx's ``get(url, *, params)`` returning a
    response with ``.raise_for_status()`` and ``.json()`` — the real authed
    httpx client in production, a fake in tests.
    """
    repositories: list[dict[str, Any]] = []
    page = 1
    while True:
        resp = client.get(
            _INSTALLATION_REPOS_PATH,
            params={"per_page": _PER_PAGE, "page": page},
        )
        resp.raise_for_status()
        body = resp.json()
        batch = body.get("repositories", [])
        if not batch:
            break
        repositories.extend(batch)
        # A short page means we've reached the end; stop before an empty request.
        if len(batch) < _PER_PAGE:
            break
        page += 1
    return repositories


def list_installation_repos(token: str) -> list[str]:
    """Return ``owner/name`` slugs for every repo the App installation can access.

    Reuses :class:`frankenbot.githubapp.GitHubClient` for auth + transport.
    """
    with githubapp.GitHubClient(token) as gh:
        repositories = _collect_installation_repositories(gh.http)
    return extract_slugs(repositories)


def effective_repos(settings: Settings, token: str) -> list[RepoConfig]:
    """Resolve the effective repo policy list, honoring ``discovery`` mode.

    - ``discovery == "off"`` (default/MVP): return the explicit ``repos.yaml``
      list unchanged.
    - ``discovery == "auto"``: use the installations API as the source of truth
      and merge with explicit per-repo overrides. On ANY API failure, log and
      fall back to the explicit list (discovery is best-effort, never fatal).
    """
    if not settings.discovery_is_auto():
        return settings.repos

    try:
        slugs = list_installation_repos(token)
    except Exception:  # noqa: BLE001 - best-effort radar; degrade, do not crash
        log.exception(
            "installation-repo discovery failed; falling back to explicit repos.yaml",
            extra={"fb_repo_count": len(settings.repos)},
        )
        return settings.repos

    merged = settings.merge_discovered(slugs)
    log.info(
        "discovery resolved effective repo set",
        extra={
            "fb_discovered": len(slugs),
            "fb_explicit": len(settings.repos),
            "fb_effective": len(merged),
        },
    )
    return merged
