#!/usr/bin/env python3
# Stdlib-only helper — plain `python3` shebang (NOT `uv run`). It is invoked
# from mise tasks as `python3 scripts/app_version.py` for `$()` capture; a
# `uv run` shebang would add startup cost and project-config coupling for no
# benefit here, and (for mise *file tasks*) recursively re-invokes the runner.
"""Compute the AutoMate application version string (doit→mise migration, Phase 2).

INTENT
    Faithful port of two pieces of the former ``dodo.py`` (removed in the
    doit→mise migration, Phase 4) that together produce the image version
    consumed by ``deploy``/``plan``/``gen_version``. The "mirrors dodo's …"
    notes below document parity with that prior implementation:

      * ``_app_version()``      -> the BASE version, read verbatim from the
                                   ``<Version>`` element of ``AutoMate.fsproj``.
      * ``_setup():app_version`` -> the FULL version, assembled FRESH each run as
                                   ``{base}-{branch}.{epoch}``.

    This helper is intentionally a PLAIN script, not a mise task, so its stdout
    stays clean for command-substitution capture:

        v="$(python3 scripts/app_version.py)"        # full   -> 0.3.1-main.1750000000
        v="$(python3 scripts/app_version.py --base)" # base   -> 0.3.1

ARCHITECTURE
    base_version()  mirrors dodo's ``_app_version()``: first ``<Version>`` line wins.
    git_branch()    mirrors dodo's ``_git_branch_name(safe=True)``: walk parent
                    dirs for a ``.git/HEAD`` file, read the ``ref: refs/heads/<name>``
                    line, then sanitize with the SAME regex dodo uses.
    full_version()  mirrors dodo's ``_setup():app_version`` assembly, including the
                    ``datetime.utcnow().strftime("%s")`` epoch.

DESIGN DECISIONS / WHY
    * FRESH PER RUN: the epoch is computed at call time (never cached). A mise
      ``[env]`` ``exec()`` value would freeze the epoch across the cache TTL, so
      this stays a script invoked per task run instead.
    * BRANCH RESOLUTION matches dodo byte-for-byte — it globs ``.git/HEAD`` up the
      parent chain. In a git *worktree* the worktree's ``.git`` is a FILE (not a
      dir), so the glob skips it and resolves the main checkout's branch; this is
      the same value dodo.py would compute, preserving parity.
    * PATHS are anchored to ``__file__`` (not CWD) so the helper is correct no
      matter which directory the calling task runs from.
"""

import datetime as dt
import re
import sys
from pathlib import Path

# scripts/app_version.py -> project root (fsharp/api/automate) -> the fsproj.
PROJECT_DIR = Path(__file__).resolve().parent.parent
APP_FSPROJ = PROJECT_DIR / "AutoMate" / "AutoMate.fsproj"


def base_version() -> str:
    """Return the bare ``<Version>`` from the fsproj (mirrors ``_app_version``)."""
    with open(APP_FSPROJ) as fp:
        for line in fp:
            if "<Version>" not in line:
                continue
            return line.strip().removeprefix("<Version>").removesuffix("</Version>")
    raise RuntimeError("Could not find version")


def git_branch(*, safe: bool = True) -> str:
    """Return the current branch (mirrors ``_git_branch_name(safe=True)``)."""
    start = Path(__file__).resolve()
    git_head = next(
        git_head for parent in start.parents for git_head in parent.glob(".git/HEAD")
    )
    with git_head.open("rt") as fp:
        name = next(
            line.strip().partition("refs/heads/")[-1]
            for line in fp
            if line.startswith("ref:")
        )
    return re.sub(r"[^a-z0-9_.-]+", "-", name, flags=re.IGNORECASE) if safe else name


def full_version() -> str:
    """Assemble ``{base}-{branch}.{epoch}`` fresh (mirrors ``_setup:app_version``)."""
    base = base_version()
    branch = git_branch(safe=True)
    epoch = dt.datetime.utcnow().strftime("%s")
    return f"{base}-{branch}.{epoch}"


def main(argv: list[str]) -> int:
    if "--base" in argv:
        print(base_version())
    else:
        print(full_version())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
