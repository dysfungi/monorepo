# AGENTS.md

## Repository Overview

This repository is a monorepo organized by language at the first level and functional category at the second level.

### Structure:

- `fsharp/api/automate/`: F# API project (`AutoMate.sln`).
- `python/pipeline/build-automation/`: Python build pipeline automation.
- `terraform/`: Infrastructure (`infrastructure/frankenstructure`), Applications (`applications/`), and shared modules (`modules/`).

---

## Task Runner (`doit` / `dodo.py`)

A root `dodo.py` file defines workspace-wide tasks using `pydoit`.
Common commands:

- `doit ls`: List all available tasks and projects.
- `doit setup`: Run root setup (`mise install`, `pre-commit install`) and project-specific setups.
- `doit lint`: Run linters via `pre-commit` on all files.
- `doit build`: Build projects (can filter with `$LANGUAGE/$CATEGORY/$PROJECT`).
- `doit start`: Run projects.

---

## Environment & Secrets (`mise`)

We use `mise` (`.mise.toml`) for managing the developer environment and secrets.

- Secrets are dynamically loaded from 1Password via `op` CLI.
- Entry hook `.mise/setup.sh` bootstraps necessary files and performs docker logins.
- For the full config / secrets / CI-CD architecture (1Password → CI, `mise`, and
  the External Secrets Operator), see
  [`docs/architecture-config-secrets-cicd.md`](docs/architecture-config-secrets-cicd.md).

---

## Language Guidelines & Tooling

### Python

- **Environment & Execution:** Prefer `uv` for python scripts and dependency isolation (e.g. `#!/usr/bin/env -S uv run --script` for PEP 723 inline dependency metadata).
- **Formatters & Linters:** Managed via `pre-commit`:
  - Formatting: `black`, `isort`
  - Linting: `flake8`
  - Type-checking: `mypy` (requires dependencies: alembic, pydantic, types-pyyaml)
- **Docstrings:** Every python script must include a comprehensive module-level docstring covering intent, architecture, and design decisions.

### F# / .NET

- **Location:** `fsharp/api/automate/`
- **Formatting:** Strictly use `dotnet fantomas` for formatting `.fs` and `.fsx` files (configured via `pre-commit`).
- **Build / Tooling:** Follow solution and project dependencies managed via `.config/dotnet-tools.json`, `paket`, etc.

### Terraform / OpenTofu

- **Location:** `terraform/`
- **Tool Preference:** **Strictly prefer `tofu` (OpenTofu)** over `terraform` for all operations (formatting, validation, planning, applying).
- **Formatters & Linters:**
  - Formatting: `tofu fmt` (configured via `pre-commit`)
  - Validation: `tofu validate` (configured via `pre-commit`)

### Kubernetes

- **Verification:** Feel free to use `kubectl` to inspect, troubleshoot, and verify the live state of resources in the Kubernetes cluster (e.g., checking active pods, namespaces, Custom Resource Definitions, or logs) to ensure precise operational alignment.

---

## Workflow & Git Guidelines

### Task Tracking (`todo.txt`)

- Always maintain an active task list in `todo.txt` using the `todo.sh` CLI (e.g., `todo.sh list`, `todo.sh add`, `todo.sh do`).
- Create tasks proactively as new work surfaces. Keep the list updated and mark tasks completed promptly.

### Multi-Instance Worktrees (MANDATORY)

- Every session that modifies files MUST use an isolated git worktree to avoid concurrency edit races.
  - Create worktree: `git worktree add .worktrees/<session-id>.<task-slug> -b task/<session-id>.<task-slug>`
  - Record the worktree claim in `todo.txt`: `@worktree:.claude/worktrees/<session-id>.<task-slug> session:<id> agent:<tool> model:<model-id>`
  - On completion: merge back to main with `--ff-only`, remove the worktree, and delete the task branch.

### Version Control & Commits

- **Rebase-Before-Push:** Always run `git pull --rebase` immediately before `git push`.
- **Named Stashes:** Never use bare `git stash`. Always use `git stash push -m "<unique-slug>"`.
- **Commits:** Follow Conventional Commits. Include an explicit audit section in the commit body (e.g. `Authored By`, `Model`, `Session-ID`, etc.).
- **Auto-Commits:** In implementation mode, auto-commit completed work without asking (unless user pushes back or a design/decision alignment is needed).

---

## Code Style & Conventions

- **Less is More:** Prioritize simple, concise, and clean code.
- **Fail Loudly:** Never fail silently; raise explicit, actionable errors.
- **Guard Clauses:** Prefer early-exit guard clauses over nested/spaghetti control flow.
- **Document Non-Obvious Decisions:** Document the "WHY" of non-obvious architectural choices directly in the source file (comments/docstrings) rather than relying on git history.
