#!/usr/bin/env bash
# .mise/setup.sh
#
# PURPOSE: Irreducible side effects that cannot live in mise [env] (declarative)
# because they write files to disk or perform Docker auth — not just export values.
#
# This script is sourced by mise's [[hooks.enter]] on every directory entry,
# but each block is guarded so it is a no-op after the first successful run.
#
# WHAT IS NOT HERE and WHY:
#   - Secret fetching (op read): moved to [env] exec() with cache_key for
#     cross-terminal caching; mise stores values in ~/.cache/mise.
#   - frankenstorage.yaml / frankistry.json: these only backed AWS_* and REGISTRY
#     env var values; both are now cached execs, so the files are gone.
#   - watch_file: direnv-only; mise [[watch_files]] runs a task (not env re-eval).
#     To force secret refresh: `mise cache clear`. To force kubeconfig refresh:
#     `rm secrets/frank8s.yaml` (this script re-creates it).
#
# ENV AVAILABLE: mise has already applied [env] before hooks.enter runs, so
# GITHUB_USERNAME, VULTR_API_KEY, and REGISTRY are all set.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

mkdir -p "$REPO_ROOT/secrets"

# --- frank8s.yaml (kubeconfig) -------------------------------------------
# KUBECONFIG must be a real file path — mise caches values, not files.
# Fetch only on first entry (or after manual deletion to force refresh).
KUBECONFIG_PATH="$REPO_ROOT/secrets/frank8s.yaml"
if ! test -e "$KUBECONFIG_PATH"; then
    vultr-cli --output=json kubernetes list \
        | jq --raw-output '.vke_clusters[] | select(.label == "frank8s").id' \
        | xargs vultr-cli kubernetes config \
        | base64 --decode > "$KUBECONFIG_PATH"
    chmod 600 "$KUBECONFIG_PATH"
fi

# --- docker login: ghcr.io -----------------------------------------------
# Docker persists auth to ~/.docker/config.json — one-time-ever per machine.
# Token is the 24h-cached value from [env] (TF_VAR_github_token). We deliberately
# do NOT use/export GITHUB_TOKEN: it would shadow gh's own auth with an
# under-privileged token.
if ! jq -e '.auths["ghcr.io"]' ~/.docker/config.json &>/dev/null; then
    # shellcheck disable=SC2154  # TF_VAR_github_token is injected by mise [env]
    docker login --username "$GITHUB_USERNAME" --password-stdin <<< "$TF_VAR_github_token" ghcr.io
fi

# --- docker login: frankistry (Vultr container registry) -----------------
# Fetch login creds inline; guard on existing docker auth entry.
REGISTRY_HOST="${REGISTRY%%/*}"   # strip path, keep hostname
if ! jq -e --arg h "$REGISTRY_HOST" '.auths[$h]' ~/.docker/config.json &>/dev/null; then
    REGISTRY_JSON="$(vultr-cli --output=json container-registry list \
        | jq '.registries[] | select(.name == "frankistry")')"
    docker login \
        --username "$(jq --raw-output '.root_user.username' <<< "$REGISTRY_JSON")" \
        --password-stdin <<< "$(jq --raw-output '.root_user.password' <<< "$REGISTRY_JSON")" \
        "$REGISTRY"
fi
