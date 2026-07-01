"""Unit tests for :mod:`frankenbot.triage` — the security-critical helpers.

These are the durable spec for two hardening guarantees (both defend the same
prompt-injection exfiltration path: untrusted CI logs -> agent stdout -> public
PR comment):

- ``_agent_env`` builds the ``claude`` subprocess environment from an EXPLICIT
  allowlist, so the child never inherits the GitHub App private key (or any other
  non-allowlisted secret) from the pod.
- ``_scrub`` redacts credentials — token-in-URL, PEM private-key blocks, GitHub
  token patterns, and the literal values of known secrets — before any text is
  logged or posted.
"""

from __future__ import annotations

from typing import Any

from frankenbot.triage import _agent_env, _scrub

# --- _agent_env: explicit allowlist, no inherited secrets -------------------


def test_agent_env_excludes_app_private_key(monkeypatch: Any) -> None:
    monkeypatch.setenv("FRANKENBOT_APP_PRIVATE_KEY", "-----BEGIN RSA PRIVATE KEY-----")
    monkeypatch.setenv("FRANKENBOT_APP_ID", "12345")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-secret-value-123456")
    monkeypatch.setenv("PATH", "/usr/bin:/bin")

    env = _agent_env()

    # The whole point: the App private key (and other non-allowlisted vars) are
    # withheld from the agent subprocess.
    assert "FRANKENBOT_APP_PRIVATE_KEY" not in env
    assert "FRANKENBOT_APP_ID" not in env
    # Allowlisted operational vars are forwarded.
    assert env["ANTHROPIC_API_KEY"] == "sk-ant-secret-value-123456"
    assert env["PATH"] == "/usr/bin:/bin"


def test_agent_env_forwards_otel_but_not_arbitrary_vars(monkeypatch: Any) -> None:
    monkeypatch.setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://collector:4317")
    monkeypatch.setenv("SOME_OTHER_SECRET", "nope")
    monkeypatch.setenv("PATH", "/usr/bin")

    env = _agent_env()

    assert env["OTEL_EXPORTER_OTLP_ENDPOINT"] == "http://collector:4317"
    assert "SOME_OTHER_SECRET" not in env


# --- _scrub: redact every credential shape ---------------------------------


def test_scrub_redacts_pem_block() -> None:
    text = (
        "leaked:\n-----BEGIN RSA PRIVATE KEY-----\n"
        "MIIEowIBAAKCAQEA...\nabc123\n-----END RSA PRIVATE KEY-----\ndone"
    )
    scrubbed = _scrub(text)
    assert "PRIVATE KEY" not in scrubbed
    assert "MIIEowIBAAKCAQEA" not in scrubbed
    assert "<redacted-private-key>" in scrubbed
    assert scrubbed.startswith("leaked:")
    assert scrubbed.endswith("done")


def test_scrub_redacts_github_token() -> None:
    text = "here is a token ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 in the logs"
    scrubbed = _scrub(text)
    assert "ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" not in scrubbed
    assert "<redacted-gh-token>" in scrubbed


def test_scrub_redacts_anthropic_key_literal(monkeypatch: Any) -> None:
    secret = "sk-ant-api03-super-secret-value-abcdef"
    monkeypatch.setenv("ANTHROPIC_API_KEY", secret)
    scrubbed = _scrub(f"the model printed {secret} oops")
    assert secret not in scrubbed
    assert "<redacted-secret>" in scrubbed


def test_scrub_redacts_extra_secret_minted_token() -> None:
    # The minted installation token never lives in the environment, so it is
    # passed via extra_secrets and must still be redacted wherever it appears.
    token = "v1.a-freshly-minted-token-1234567890"
    scrubbed = _scrub(f"remote said {token}", extra_secrets=(token,))
    assert token not in scrubbed
    assert "<redacted-secret>" in scrubbed


def test_scrub_redacts_token_in_url() -> None:
    text = "https://x-access-token:ghs_TOKENVALUE1234567890@github.com/o/r.git"
    scrubbed = _scrub(text)
    assert "ghs_TOKENVALUE1234567890" not in scrubbed
    assert "x-access-token:<redacted>@" in scrubbed
