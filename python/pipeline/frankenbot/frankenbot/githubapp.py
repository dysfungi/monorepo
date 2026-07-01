"""GitHub App authentication and a thin authed REST client for Frankenbot.

Intent
------
Mint a short-lived GitHub App *installation* access token entirely in-process
(no external sidecar), then expose the handful of REST calls the dispatcher and
triage worker need: list PRs, list check-runs for a ref, add labels, and create
issue comments.

Architecture
------------
1. Build an RS256-signed JWT from the App ID + PEM private key (PyJWT +
   cryptography backend). The JWT authenticates *as the App*.
2. Exchange the JWT for an installation token via
   ``POST /app/installations/{id}/access_tokens``. That token authenticates *as
   the installation* and is what the REST helpers use.
3. ``GitHubClient`` wraps httpx with the token and the standard GitHub headers.

Design decisions
----------------
- SECURITY: the token and PEM are NEVER logged. Callers must not interpolate the
  token into log lines. The clone URL in ``triage`` embeds the token but is
  scrubbed before any logging.
- Fail loudly: every required env var is checked up front with an actionable
  error; HTTP errors raise ``httpx.HTTPStatusError`` via ``raise_for_status``.
- JWT lifetime is clamped to GitHub's 10-minute maximum, backdated 60s to
  tolerate minor clock skew (documented GitHub guidance).
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Any

import httpx
import jwt

GITHUB_API = "https://api.github.com"
_ACCEPT = "application/vnd.github+json"
_API_VERSION = "2022-11-28"
_USER_AGENT = "frankenbot/0.1"

# GitHub caps App JWT lifetime at 10 minutes; backdate to absorb clock skew.
_JWT_TTL_SECONDS = 9 * 60
_JWT_BACKDATE_SECONDS = 60

_HTTP_TIMEOUT = httpx.Timeout(30.0, connect=10.0)


@dataclass(frozen=True)
class InstallationToken:
    """A minted installation token and its ISO-8601 expiry timestamp."""

    token: str
    expires_at: str

    def __repr__(self) -> str:  # pragma: no cover - trivial
        # Guard against accidental token leakage via repr in logs/tracebacks.
        return f"InstallationToken(token=<redacted>, expires_at={self.expires_at!r})"


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(
            f"{name} is required to authenticate as the GitHub App but is unset/empty."
        )
    return value


def _build_app_jwt(app_id: str, private_key_pem: str) -> str:
    """Return an RS256-signed App JWT. Never logs the key or the token."""
    now = int(time.time())
    payload = {
        "iat": now - _JWT_BACKDATE_SECONDS,
        "exp": now + _JWT_TTL_SECONDS,
        "iss": app_id,
    }
    try:
        token: str = jwt.encode(payload, private_key_pem, algorithm="RS256")
        return token
    except Exception as exc:  # noqa: BLE001 - surface a clean, key-free error
        raise ValueError(
            "failed to sign GitHub App JWT; verify "
            "FRANKENBOT_APP_PRIVATE_KEY is a valid unencrypted RSA PEM."
        ) from exc


def mint_installation_token() -> InstallationToken:
    """Mint a short-lived installation token from Frankenbot's App credentials.

    Reads ``FRANKENBOT_APP_ID``, ``FRANKENBOT_APP_PRIVATE_KEY`` (PEM string), and
    ``FRANKENBOT_APP_INSTALLATION_ID`` from the environment. Fails loud if any is
    missing.
    """
    app_id = _require_env("FRANKENBOT_APP_ID")
    private_key = _require_env("FRANKENBOT_APP_PRIVATE_KEY")
    installation_id = _require_env("FRANKENBOT_APP_INSTALLATION_ID")

    app_jwt = _build_app_jwt(app_id, private_key)
    url = f"{GITHUB_API}/app/installations/{installation_id}/access_tokens"
    headers = {
        "Accept": _ACCEPT,
        "Authorization": f"Bearer {app_jwt}",
        "X-GitHub-Api-Version": _API_VERSION,
        "User-Agent": _USER_AGENT,
    }

    with httpx.Client(timeout=_HTTP_TIMEOUT) as client:
        resp = client.post(url, headers=headers)
    # Do not include the response body verbatim in raised errors: it is safe here
    # (no secrets echoed), but keep the message stable and actionable.
    if resp.status_code != 201:
        raise RuntimeError(
            f"minting installation token failed: HTTP {resp.status_code} "
            f"(installation_id={installation_id})."
        )

    body = resp.json()
    token = body.get("token")
    expires_at = body.get("expires_at", "")
    if not token:
        raise RuntimeError(
            "installation token response did not contain a 'token' field."
        )
    return InstallationToken(token=token, expires_at=expires_at)


class GitHubClient:
    """Thin authenticated GitHub REST client scoped to an installation token."""

    def __init__(self, token: str) -> None:
        self._client = httpx.Client(
            base_url=GITHUB_API,
            timeout=_HTTP_TIMEOUT,
            headers={
                "Accept": _ACCEPT,
                "Authorization": f"token {token}",
                "X-GitHub-Api-Version": _API_VERSION,
                "User-Agent": _USER_AGENT,
            },
        )

    def __enter__(self) -> "GitHubClient":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def close(self) -> None:
        self._client.close()

    @property
    def http(self) -> httpx.Client:
        """The underlying authed httpx client.

        Exposed so sibling modules (e.g. ``frankenbot.discovery``) can issue
        additional authenticated GET calls without re-minting a token or
        duplicating the base URL / header / timeout setup.
        """
        return self._client

    # -- reads ---------------------------------------------------------------

    def get_pull(self, repo: str, pr_number: int) -> dict[str, Any]:
        """Fetch a single PR by number."""
        resp = self._client.get(f"/repos/{repo}/pulls/{pr_number}")
        resp.raise_for_status()
        pull: dict[str, Any] = resp.json()
        return pull

    def list_open_pulls(
        self, repo: str, label: str | None = None
    ) -> list[dict[str, Any]]:
        """List OPEN PRs for ``OWNER/NAME``, optionally filtered by a label.

        The ``/repos/{repo}/pulls`` endpoint has no label filter, so we page
        through it and, when ``label`` is given, post-filter the results by label
        name client-side.
        """
        pulls: list[dict[str, Any]] = []
        page = 1
        while True:
            resp = self._client.get(
                f"/repos/{repo}/pulls",
                params={"state": "open", "per_page": 100, "page": page},
            )
            resp.raise_for_status()
            batch = resp.json()
            if not batch:
                break
            pulls.extend(batch)
            page += 1

        if label is None:
            return pulls
        return [
            p
            for p in pulls
            if any(lbl.get("name") == label for lbl in p.get("labels", []))
        ]

    def list_check_runs(self, repo: str, ref: str) -> list[dict[str, Any]]:
        """List check-runs for a commit ``ref`` (head SHA)."""
        runs: list[dict[str, Any]] = []
        page = 1
        while True:
            resp = self._client.get(
                f"/repos/{repo}/commits/{ref}/check-runs",
                params={"per_page": 100, "page": page},
            )
            resp.raise_for_status()
            body = resp.json()
            batch = body.get("check_runs", [])
            if not batch:
                break
            runs.extend(batch)
            if len(batch) < 100:
                break
            page += 1
        return runs

    def get_actions_run_logs(self, repo: str, run_id: int) -> bytes | None:
        """Download a GitHub Actions run's logs (zip). Returns None if unavailable.

        Best-effort: logs expire and permissions vary, so callers fall back to
        the check-run summary text when this returns None.
        """
        resp = self._client.get(
            f"/repos/{repo}/actions/runs/{run_id}/logs",
            follow_redirects=True,
        )
        if resp.status_code != 200:
            return None
        return resp.content

    # -- writes --------------------------------------------------------------

    def add_labels(self, repo: str, issue_number: int, labels: list[str]) -> None:
        """Add labels to a PR/issue (additive; does not remove existing labels)."""
        resp = self._client.post(
            f"/repos/{repo}/issues/{issue_number}/labels",
            json={"labels": labels},
        )
        resp.raise_for_status()

    def create_issue_comment(self, repo: str, issue_number: int, body: str) -> None:
        """Post a comment on a PR/issue."""
        resp = self._client.post(
            f"/repos/{repo}/issues/{issue_number}/comments",
            json={"body": body},
        )
        resp.raise_for_status()
