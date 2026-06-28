# monorepo

[![CI/CD Workflow][cicd-workflow-badge]][cicd-workflow]
[![healthchecks.io][healthchecksio-badge]][healthchecksio-check]

## Prerequisites & Tooling

The dev toolchain is managed by [`mise`](https://mise.jdx.dev/) — `mise install` provisions every pinned tool in `.mise.toml [tools]` (kubectl, helm, opentofu, dotnet, python, vultr-cli, etc.). `mise run setup` runs `mise install` + `pre-commit install`.

A few things mise cannot bootstrap and must be installed manually first:

- **mise** itself — the toolchain manager ([install docs](https://mise.jdx.dev/getting-started.html)).
- **1Password CLI (`op`)** — `.mise.toml` loads secrets from 1Password on shell enter.
- **Docker** (with `docker compose`) — used by `.mise/setup.sh` and several `mise` tasks.

Linters/formatters (black, isort, flake8, mypy, prettier, gitlint, yamllint, yamlfmt, shellcheck, fantomas) are installed automatically by `pre-commit` in isolated environments — no manual setup needed.

## organization

This repository is a [monorepo][awesome-monorepo] (not monolith) of my
programs using a
[hybrid approach](https://www.rocketpoweredjetpants.com/2017/11/organising-a-monorepo/#blended-monorepos)
of organization where the first level groups projects under the language
they are primarily written in (e.g., fsharp, python, terraform) and the
second is the functional area the projects are categorized as (e.g.,
api, infrastructure).

```
fsharp/api/automate/
terraform/infrastructure/frankenstructure
```

## github actions

### local testing with `act`

You can run and test GitHub Actions workflows locally using **`act`** (by nektos).
Run the pipeline locally (requires Docker):

```bash
act push
```

### 1password secrets

- [Load secrets from GitHub Actions | 1Password Docs][op-github-actions-docs]
- [Load secrets from 1Password | GitHub Actions][github-action-op-load-secrets]

> **Architecture:** see
> [docs/architecture-config-secrets-cicd.md](docs/architecture-config-secrets-cicd.md)
> for how config, secrets (1Password → CI / `mise` / ESO), and CI/CD fit
> together.

## deployments

Infrastructure and applications deploy via GitHub Actions
([`.github/workflows/cicd.yaml`](.github/workflows/cicd.yaml)) on push to
`main` (GitOps):

- **Path-filtered:** commits touching no deployable path don't deploy. Only
  changed application stacks are redeployed.
- **Always-on foundation:** the frankenstructure, gateway, and observability
  stacks always apply, serving as the credential substrate for the rest.
- **Remote state:** stored on Vultr Object Storage (S3-compatible) with
  `use_lockfile` state locking.

---

[awesome-monorepo]: https://github.com/korfuri/awesome-monorepo?tab=readme-ov-file
[cicd-workflow-badge]: https://github.com/dysfungi/monorepo/actions/workflows/cicd.yaml/badge.svg
[cicd-workflow]: https://github.com/dysfungi/monorepo/actions/workflows/cicd.yaml
[github-action-op-load-secrets]: https://github.com/marketplace/actions/load-secrets-from-1password
[healthchecksio-badge]: https://healthchecks.io/b/2/eeb33c94-7b23-4296-9955-9dac2aebca6e.svg
[healthchecksio-check]: https://healthchecks.io/checks/d6111af4-d2aa-4bd5-ac84-4533b2ce8680/details/
[op-github-actions-docs]: https://developer.1password.com/docs/ci-cd/github-actions/
