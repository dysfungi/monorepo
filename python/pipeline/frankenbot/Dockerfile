# Frankenbot agent image.
#
# Design: intentionally SLIM. We bake only the two runtimes the platform itself
# needs — Node (for the Claude Code CLI) and Python 3.12 (for the frankenbot
# package) — plus git and a minimal toolbelt. Per-repo language toolchains are
# NOT baked; they are resolved on demand at triage time via `mise` inside the
# cloned repo. This keeps the image small and avoids toolchain drift.
#
# Base is node:22-slim (Debian bookworm) because the Claude CLI is a Node
# package. Debian bookworm's ``python3`` is 3.11, but the frankenbot package
# requires >=3.12 (see pyproject.toml). We therefore do NOT use the distro
# Python: uv installs a pinned CPython 3.12 into a STABLE, copyable location and
# builds the venv against it, so the interpreter travels to the runtime image.

# ---- builder: create a self-contained venv with the frankenbot package -------
FROM node:22-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # Pin uv's managed-interpreter install dir to a stable path so the venv's
    # python symlink resolves after we COPY it into the runtime image.
    UV_PYTHON_INSTALL_DIR=/opt/uv-python

# Build deps: curl + ca-certificates for the uv installer. No distro Python and
# no compiler — every runtime dependency ships a manylinux wheel for cpython3.12
# (psycopg[binary], cryptography, pydantic-core, PyYAML), so uv installs from
# wheels with nothing to build.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast, reproducible Python installs) into a stable location.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Install a pinned CPython 3.12 (matches requires-python >=3.12).
RUN /usr/local/bin/uv python install 3.12

WORKDIR /src
COPY pyproject.toml ./
COPY frankenbot ./frankenbot

# Build an isolated venv on 3.12 and install the package into it. Using a venv
# (rather than --system) keeps the runtime image portable; the venv's python
# symlinks into /opt/uv-python, which we copy alongside it into the final image.
RUN /usr/local/bin/uv venv --python 3.12 /opt/frankenbot-venv \
    && /usr/local/bin/uv pip install --python /opt/frankenbot-venv/bin/python .

# ---- runtime: slim final image ----------------------------------------------
FROM node:22-slim AS final

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/frankenbot-venv/bin:${PATH}" \
    # The Claude CLI reads its config (CLAUDE.md + skills) from here.
    CLAUDE_CONFIG_DIR="/home/frankenbot/.claude" \
    WORKSPACE_DIR="/workspace"

# Runtime toolbelt only. ripgrep powers the agent's Grep tool; jq/openssh/curl
# are common triage utilities; git is required for clone/commit/push. unzip and
# gnupg are required by the OpenTofu standalone installer below: it unzips the
# release archive (fails "Unzip is missing" without unzip) and GPG-verifies the
# signed download (it aborts when neither cosign nor GPG is on PATH). NOTE: no
# distro python3 — the frankenbot venv (copied below) ships its own pinned 3.12,
# and a stray Debian 3.11 would only be a misleading, unused interpreter.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        ripgrep \
        openssh-client \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Install mise (per-repo toolchain resolution) and OpenTofu (tofu) leanly.
# mise resolves language runtimes on demand inside the cloned repo at triage time.
# The standalone installer places the binary in --install-path and drops a
# symlink in --symlink-path; these MUST differ (pointing both at /usr/local/bin
# makes it try to symlink tofu onto itself: "ln: ... are the same file"). So the
# binary lives in /opt/opentofu and the symlink lands on PATH at /usr/local/bin.
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-tofu.sh \
    && chmod +x /tmp/install-tofu.sh \
    && /tmp/install-tofu.sh --install-method standalone --install-path /opt/opentofu --symlink-path /usr/local/bin \
    && rm -f /tmp/install-tofu.sh

# Install the Claude Code CLI globally (Node package).
RUN npm install -g @anthropic-ai/claude-code \
    && npm cache clean --force

# Bring in the frankenbot venv from the builder, plus the pinned CPython 3.12 it
# symlinks to. Both land at the same absolute paths as in the builder, so the
# venv's ``bin/python`` symlink (and the ``frankenbot`` console-script shebang)
# resolve and run on 3.12.
COPY --from=builder /opt/uv-python /opt/uv-python
COPY --from=builder /opt/frankenbot-venv /opt/frankenbot-venv

# Non-root runtime user. UID 1001 (not 1000): the node:22-slim base already
# ships a `node` user at UID 1000, so `useradd --uid 1000` fails with "UID
# already in use" (exit 4). Nothing pins runAsUser in the k8s podSpec, so the
# exact number is not load-bearing — it only has to be a stable non-root uid.
RUN useradd --create-home --uid 1001 --shell /bin/bash frankenbot

# Bake the curated, headless-safe agent config (CLAUDE.md + skills) so the CLI
# picks them up from CLAUDE_CONFIG_DIR.
COPY --chown=frankenbot:frankenbot agent-skills/ /home/frankenbot/.claude/
# Also ship the default repo policy list at the conventional path (a ConfigMap
# overrides this in-cluster).
COPY --chown=frankenbot:frankenbot repos.yaml /etc/frankenbot/repos.yaml

WORKDIR /workspace
RUN chown frankenbot:frankenbot /workspace

USER frankenbot

ENTRYPOINT ["frankenbot"]
