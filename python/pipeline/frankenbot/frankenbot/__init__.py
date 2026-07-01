"""Frankenbot: an in-cluster agentic dependency-maintenance platform.

Intent
------
Frankenbot triages Renovate-authored dependency-bump pull requests whose CI has
gone RED. It is a single container image with two runtime modes (see
``frankenbot.cli``):

- ``dispatch`` — a Kubernetes CronJob that finds failing, un-triaged Renovate
  PRs and fans out one ephemeral triage Job per PR.
- ``triage`` — the ephemeral Job that reads the failing CI logs, attempts at
  most one fix commit, and otherwise posts a structured triage comment. It
  always labels the PR.

Design decisions
----------------
- MVP is strictly PROPOSE-ONLY: nothing here auto-merges. Humans merge.
- One image, two modes: keeps build/deploy surface minimal (tracer-bullet MVP).
- OpenTelemetry is optional/best-effort (see ``frankenbot.otel``).
"""

__version__ = "0.1.0"

__all__ = ["__version__"]
