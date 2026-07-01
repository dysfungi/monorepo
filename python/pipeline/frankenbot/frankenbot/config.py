"""Configuration models and environment loading for Frankenbot.

Intent
------
Centralize every tunable — kill switch, namespace, concurrency, image, node
placement, and the per-repo policy list — behind typed, validated models so the
rest of the codebase never reaches into ``os.environ`` ad hoc.

Architecture
------------
- ``RepoConfig``: one entry from ``repos.yaml`` describing a repository Frankenbot
  is allowed to act on and at what tier.
- ``Settings``: process-wide settings hydrated from environment variables, with
  the repo list loaded from a YAML file on disk (a k8s ConfigMap mount in
  production).

Design decisions
----------------
- pydantic v2 models give us fail-loud validation: a missing required value
  (e.g. ``FRANKENBOT_IMAGE`` in-cluster) raises immediately with an actionable
  message rather than surfacing as a confusing k8s error later.
- The infrastructure node-pool selector is a single centralized constant. The
  assumed Vultr VKE label is ``vke.vultr.com/node-pool=infrastructure`` — VERIFY
  the real label at deploy time (see ``INFRA_NODEPOOL_LABEL_DEFAULT``).
- Unlisted repos are NOT implicitly actionable. Only repos present and enabled
  in ``repos.yaml`` are dispatched against. The default *tier* for a listed repo
  is ``propose-only`` (auto-merge tiers arrive in a later phase).
"""

from __future__ import annotations

import os
from pathlib import Path

import yaml
from pydantic import BaseModel, Field, ValidationError

# ---------------------------------------------------------------------------
# Centralized constants
# ---------------------------------------------------------------------------

# The infrastructure node pool selector. Triage Jobs MUST land on this pool.
#
# VERIFY AT DEPLOY TIME: this is the *assumed* Vultr VKE node-pool label. Confirm
# the live label key/value with:
#     kubectl get nodes --show-labels | tr ',' '\n' | grep node-pool
# and update this constant if it differs.
INFRA_NODEPOOL_LABEL_DEFAULT = "vke.vultr.com/node-pool=infrastructure"

# Default on-disk location of the repo policy list (a ConfigMap mount in prod).
REPOS_FILE_DEFAULT = "/etc/frankenbot/repos.yaml"

# Labels Frankenbot reads/writes on PRs.
LABEL_FRANKENBOT = "frankenbot"  # Renovate PRs carry this; our work queue.
LABEL_TRIAGED = "triaged"  # Set once a PR has been triaged (idempotency guard).
LABEL_NEEDS_HUMAN = "needs-human"  # Set when triage could not auto-fix.


def _env_bool(name: str, default: bool) -> bool:
    """Parse a boolean env var, treating common truthy/falsey spellings.

    Fails loud on an unrecognized value rather than silently defaulting.
    """
    raw = os.environ.get(name)
    if raw is None:
        return default
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(
        f"Environment variable {name}={raw!r} is not a valid boolean "
        f"(expected one of: 1/0, true/false, yes/no, on/off)."
    )


class RepoConfig(BaseModel):
    """Policy for a single repository Frankenbot may act on."""

    name: str = Field(..., description="Repository in OWNER/NAME form.")
    tier: str = Field(
        default="propose-only",
        description="Action tier. MVP supports only 'propose-only'.",
    )
    surfaces: list[str] = Field(
        default_factory=list,
        description="Dependency surfaces in scope (e.g. github-actions, dockerfile).",
    )
    enabled: bool = Field(
        default=True, description="Whether Frankenbot dispatches on it."
    )

    def slug(self) -> str:
        """Return a DNS-1123-friendly slug of the repo *name* component.

        Uses only the NAME half of OWNER/NAME; the dispatcher combines this with
        the PR number and a hash if the result would exceed length limits.
        """
        tail = self.name.split("/", 1)[-1]
        return "".join(c if c.isalnum() else "-" for c in tail.lower()).strip("-")


class Settings(BaseModel):
    """Process-wide runtime settings hydrated from the environment."""

    enabled: bool = Field(default=True, description="Global kill switch.")
    namespace: str = Field(
        default="frankenbot", description="Namespace for triage Jobs."
    )
    max_concurrent_jobs: int = Field(
        default=1, ge=1, description="Cap on simultaneously-active triage Jobs."
    )
    daily_spend_cap_cents: int = Field(
        default=1_000_000_000,
        ge=0,
        description=(
            "Daily spend ceiling (cents). The dispatcher refuses to dispatch once "
            "budget_today exceeds this. Defaults effectively OFF (very high); set "
            "FRANKENBOT_DAILY_SPEND_CAP_CENTS to enable. Only enforced when "
            "DATABASE_URL is present."
        ),
    )
    image: str = Field(..., description="Container image for spawned triage Jobs.")
    infra_nodepool_label: str = Field(
        default=INFRA_NODEPOOL_LABEL_DEFAULT,
        description="key=value node-pool selector for the infrastructure pool.",
    )
    repos_file: str = Field(
        default=REPOS_FILE_DEFAULT, description="Path to repos.yaml."
    )
    repos: list[RepoConfig] = Field(
        default_factory=list, description="Loaded repo policies."
    )

    def nodepool_key_value(self) -> tuple[str, str]:
        """Split ``infra_nodepool_label`` into (key, value).

        Fails loud if the label is malformed.
        """
        if "=" not in self.infra_nodepool_label:
            raise ValueError(
                f"FRANKENBOT_INFRA_NODEPOOL_LABEL={self.infra_nodepool_label!r} "
                f"must be in 'key=value' form (e.g. {INFRA_NODEPOOL_LABEL_DEFAULT!r})."
            )
        key, _, value = self.infra_nodepool_label.partition("=")
        key, value = key.strip(), value.strip()
        if not key or not value:
            raise ValueError(
                f"FRANKENBOT_INFRA_NODEPOOL_LABEL={self.infra_nodepool_label!r} "
                f"has an empty key or value."
            )
        return key, value

    def enabled_repos(self) -> list[RepoConfig]:
        """Return only the repos that are enabled for dispatch."""
        return [r for r in self.repos if r.enabled]


def _load_repos(repos_file: str) -> list[RepoConfig]:
    """Load and validate the repo policy list from ``repos_file``.

    Fails loud if the file is missing or malformed — a silent empty list would
    make the dispatcher a confusing no-op.
    """
    path = Path(repos_file)
    if not path.is_file():
        raise FileNotFoundError(
            f"repos file not found at {repos_file!r}. Set FRANKENBOT_REPOS_FILE "
            f"or mount the frankenbot-config ConfigMap at {REPOS_FILE_DEFAULT}."
        )

    raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(raw, dict):
        raise ValueError(
            f"repos file {repos_file!r} must be a YAML mapping with a 'repos' key."
        )

    entries = raw.get("repos", [])
    if not isinstance(entries, list):
        raise ValueError(f"'repos' in {repos_file!r} must be a list.")

    try:
        return [RepoConfig.model_validate(entry) for entry in entries]
    except ValidationError as exc:  # pragma: no cover - exercised via bad config
        raise ValueError(f"invalid repo entry in {repos_file!r}: {exc}") from exc


def load_settings() -> Settings:
    """Build ``Settings`` from the environment and the on-disk repo list.

    Design: the kill switch (``FRANKENBOT_ENABLED``) is read here so that even a
    fully-broken config still lets the dispatcher exit cleanly when disabled.
    """
    enabled = _env_bool("FRANKENBOT_ENABLED", True)
    repos_file = os.environ.get("FRANKENBOT_REPOS_FILE", REPOS_FILE_DEFAULT)

    image = os.environ.get("FRANKENBOT_IMAGE")
    if not image:
        raise ValueError(
            "FRANKENBOT_IMAGE is required (the container image used for spawned triage "
            "Jobs). It is injected in-cluster from the dispatcher's own pod spec."
        )

    max_concurrent_raw = os.environ.get("FRANKENBOT_MAX_CONCURRENT_JOBS", "1")
    try:
        max_concurrent = int(max_concurrent_raw)
    except ValueError as exc:
        raise ValueError(
            f"FRANKENBOT_MAX_CONCURRENT_JOBS={max_concurrent_raw!r} is not an integer."
        ) from exc

    spend_cap_raw = os.environ.get("FRANKENBOT_DAILY_SPEND_CAP_CENTS", "1000000000")
    try:
        spend_cap = int(spend_cap_raw)
    except ValueError as exc:
        raise ValueError(
            f"FRANKENBOT_DAILY_SPEND_CAP_CENTS={spend_cap_raw!r} is not an integer."
        ) from exc

    return Settings(
        enabled=enabled,
        namespace=os.environ.get("FRANKENBOT_NAMESPACE", "frankenbot"),
        max_concurrent_jobs=max_concurrent,
        daily_spend_cap_cents=spend_cap,
        image=image,
        infra_nodepool_label=os.environ.get(
            "FRANKENBOT_INFRA_NODEPOOL_LABEL", INFRA_NODEPOOL_LABEL_DEFAULT
        ),
        repos_file=repos_file,
        repos=_load_repos(repos_file),
    )
