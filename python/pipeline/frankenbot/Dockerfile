# Frankenbot agent image.
#
# Design: intentionally SLIM. We bake only the two runtimes the platform itself
# needs — Node (for the Claude Code CLI) and Python 3.12 (for the frankenbot
# package) — plus git and a minimal toolbelt. Per-repo language toolchains are
# NOT baked; they are resolved on demand at triage time via `mise` inside the
# cloned repo. This keeps the image small and avoids toolchain drift.
#
# Base is node:22-slim (Debian bookworm) because the Claude CLI is a Node
# package; Debian bookworm ships Python 3.12 via the deadsnakes-free default
# only on trixie, so we install Python from the distro packages available.

# ---- builder: create a self-contained venv with the frankenbot package -------
FROM node:22-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Build deps: python + venv + curl for the uv installer.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        python3 \
        python3-venv \
        python3-dev \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast, reproducible Python installs) into a stable location.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

WORKDIR /src
COPY pyproject.toml ./
COPY frankenbot ./frankenbot

# Build an isolated venv and install the package into it. Using a venv (rather
# than --system) keeps the runtime image's system Python pristine and portable.
RUN python3 -m venv /opt/frankenbot-venv \
    && /usr/local/bin/uv pip install --python /opt/frankenbot-venv/bin/python .

# ---- runtime: slim final image ----------------------------------------------
FROM node:22-slim AS final

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/frankenbot-venv/bin:${PATH}" \
    # The Claude CLI reads its config (CLAUDE.md + skills) from here.
    CLAUDE_CONFIG_DIR="/home/frankenbot/.claude" \
    WORKSPACE_DIR="/workspace"

# Runtime toolbelt only. ripgrep powers the agent's Grep tool; jq/openssh/curl
# are common triage utilities; git is required for clone/commit/push.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        ripgrep \
        openssh-client \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Install mise (per-repo toolchain resolution) and OpenTofu (tofu) leanly.
# mise resolves language runtimes on demand inside the cloned repo at triage time.
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-tofu.sh \
    && chmod +x /tmp/install-tofu.sh \
    && /tmp/install-tofu.sh --install-method standalone --install-path /usr/local/bin \
    && rm -f /tmp/install-tofu.sh

# Install the Claude Code CLI globally (Node package).
RUN npm install -g @anthropic-ai/claude-code \
    && npm cache clean --force

# Bring in the frankenbot venv from the builder.
COPY --from=builder /opt/frankenbot-venv /opt/frankenbot-venv

# Non-root runtime user.
RUN useradd --create-home --uid 1000 --shell /bin/bash frankenbot

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
