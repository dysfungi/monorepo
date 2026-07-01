"""Best-effort OpenTelemetry helper for Frankenbot.

Intent
------
Provide a single ``maybe_span(name)`` context manager that emits an OTel span
when tracing is available and configured, and otherwise does nothing at all.

Design decisions
----------------
- OTel is NOT a hard dependency (see ``pyproject.toml``). All imports are guarded
  so the module imports cleanly whether or not the SDK is installed.
- Tracing activates only when BOTH the libraries are importable AND
  ``OTEL_EXPORTER_OTLP_ENDPOINT`` is set. This mirrors the platform convention
  of "no endpoint configured => telemetry is off" and avoids noisy exporter
  errors in local/dev runs.
- The no-op path is deliberately zero-cost and never raises: observability must
  never take down the maintenance workload.
"""

from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Any, Iterator

# Guarded import: the SDK may be entirely absent in the slim image. We bind the
# trace module (or None) onto a deliberately ``Any``-typed name so the module
# type-checks cleanly whether or not opentelemetry is installed — no per-line
# ``type: ignore`` needed for either scenario.
_trace: Any = None
_OTEL_IMPORTABLE = False
try:  # pragma: no cover - exercised implicitly by presence/absence of the lib
    from opentelemetry import trace as _imported_trace

    _trace = _imported_trace
    _OTEL_IMPORTABLE = True
except Exception:  # noqa: BLE001 - any import failure => tracing off
    pass


def _tracing_enabled() -> bool:
    """Return True only when OTel is importable and an OTLP endpoint is set."""
    return _OTEL_IMPORTABLE and bool(os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"))


@contextmanager
def maybe_span(name: str, **attributes: Any) -> Iterator[None]:
    """Context manager yielding an OTel span if enabled, else a no-op.

    Never raises on the telemetry path — any exporter/SDK error is swallowed so
    the wrapped work is unaffected. Exceptions from the *wrapped body* propagate
    normally (and are recorded on the span when tracing is active).
    """
    if not _tracing_enabled():
        yield
        return

    tracer = _trace.get_tracer("frankenbot")
    with tracer.start_as_current_span(name) as span:
        try:
            for key, value in attributes.items():
                span.set_attribute(key, value)
        except Exception:  # noqa: BLE001 - attribute set must never break work
            pass
        yield
