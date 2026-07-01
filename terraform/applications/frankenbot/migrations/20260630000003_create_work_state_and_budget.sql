-- migrate:up
-- Durable frankenbot state.
--
-- work_state: one row per (repo, surface) unit of maintenance work. Drives
-- cross-run dedup (fingerprint) and records the last dispatch/outcome so the
-- dispatcher does not re-triage identical content on every 30-minute tick.
CREATE TABLE IF NOT EXISTS public.work_state
( repo        text        NOT NULL
, surface     text        NOT NULL
, last_run    timestamptz
, last_pr     int
, status      text
, fingerprint text
, ttl_hours   int
, tokens_used bigint      NOT NULL DEFAULT 0
, spend_cents bigint      NOT NULL DEFAULT 0
, updated_at  timestamptz NOT NULL DEFAULT now()
, PRIMARY KEY (repo, surface)
);

-- Dedup lookups hit (repo, surface, fingerprint); the PK already covers the
-- (repo, surface) prefix, so a dedicated fingerprint index keeps the equality
-- probe cheap without duplicating the leading key.
CREATE INDEX IF NOT EXISTS work_state_fingerprint_idx
  ON public.work_state (fingerprint);

-- budget_daily: per-UTC-day token/spend accumulation, consulted by the
-- dispatcher's daily budget gate.
CREATE TABLE IF NOT EXISTS public.budget_daily
( day         date   NOT NULL
, tokens_used bigint NOT NULL DEFAULT 0
, spend_cents bigint NOT NULL DEFAULT 0
, PRIMARY KEY (day)
);

-- migrate:down
DROP TABLE IF EXISTS public.budget_daily;
DROP INDEX IF EXISTS work_state_fingerprint_idx;
DROP TABLE IF EXISTS public.work_state;
