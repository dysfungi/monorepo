"""Command-line entrypoint for the Frankenbot container.

Intent
------
Expose the two runtime modes as argparse subcommands behind a single ``main()``:

- ``dispatch`` — the CronJob dispatcher (see ``frankenbot.dispatch``).
- ``triage --repo OWNER/NAME --pr N`` — the per-PR worker (see
  ``frankenbot.triage``).

Design decisions
----------------
- Structured logging: logs are emitted as single-line JSON objects to stdout so
  they are trivially ingestible by the cluster log pipeline. No secrets are ever
  logged (see ``githubapp``/``triage`` for token scrubbing).
- Guard clauses / fail loud: unknown or missing arguments cause a non-zero exit
  with an actionable message rather than defaulting silently.
- ``main()`` returns an int exit code; the console-script wrapper passes it to
  ``sys.exit``.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from typing import Sequence

_LOG_CONFIGURED = False


class _JsonLineFormatter(logging.Formatter):
    """Format each log record as a compact single-line JSON object."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        # Merge any structured extras attached via logger.<level>(..., extra={...}).
        for key, value in getattr(record, "__dict__", {}).items():
            if key.startswith("fb_"):
                payload[key[3:]] = value
        return json.dumps(payload, default=str, sort_keys=True)


def setup_logging(level: int = logging.INFO) -> None:
    """Install the JSON-line formatter on the root logger (idempotent)."""
    global _LOG_CONFIGURED
    if _LOG_CONFIGURED:
        return
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JsonLineFormatter())
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)
    _LOG_CONFIGURED = True


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="frankenbot",
        description="Frankenbot: agentic dependency-maintenance (propose-only MVP).",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("dispatch", help="Find failing Renovate PRs and spawn triage Jobs.")

    triage = sub.add_parser(
        "triage", help="Triage a single failing PR (ephemeral Job)."
    )
    triage.add_argument(
        "--repo",
        required=True,
        metavar="OWNER/NAME",
        help="Repository in OWNER/NAME form.",
    )
    triage.add_argument(
        "--pr",
        required=True,
        type=int,
        metavar="N",
        help="Pull request number.",
    )
    return parser


def _validate_repo(repo: str) -> None:
    """Guard: repo must be OWNER/NAME with non-empty halves."""
    owner, sep, name = repo.partition("/")
    if not sep or not owner or not name:
        raise SystemExit(f"--repo must be in OWNER/NAME form; got {repo!r}.")


def main(argv: Sequence[str] | None = None) -> int:
    """Parse args and dispatch to the selected subcommand. Returns an exit code."""
    setup_logging()
    parser = _build_parser()
    args = parser.parse_args(argv)

    # Imported lazily so that `frankenbot --help` works even if the k8s client
    # (only needed by dispatch) is unavailable in a given context.
    if args.command == "dispatch":
        from frankenbot import dispatch

        return dispatch.run()

    if args.command == "triage":
        _validate_repo(args.repo)
        if args.pr <= 0:
            raise SystemExit(f"--pr must be a positive integer; got {args.pr}.")
        from frankenbot import triage

        return triage.run(repo=args.repo, pr_number=args.pr)

    # argparse's required=True should prevent reaching here.
    parser.error(f"unknown command: {args.command!r}")
    return 2  # pragma: no cover - parser.error exits


def _console_entry() -> None:  # pragma: no cover - thin wrapper
    sys.exit(main())


if __name__ == "__main__":  # pragma: no cover
    _console_entry()
