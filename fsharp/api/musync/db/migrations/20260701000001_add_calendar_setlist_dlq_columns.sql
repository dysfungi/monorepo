-- migrate:up
-- Virtual dead-letter-queue bookkeeping. Each scheduled run self-heals transient
-- failures (operations are idempotent), so these columns only track work that
-- STAYS stuck: `*_first_failed_at` is set-once on a step's first failure and
-- cleared on its next success; `*_alerted_at` dedupes the one-shot escalation.
ALTER TABLE public.concerts
  ADD COLUMN calendar_first_failed_at timestamptz,
  ADD COLUMN calendar_alerted_at      timestamptz,
  ADD COLUMN setlist_first_failed_at  timestamptz,
  ADD COLUMN setlist_alerted_at       timestamptz;

-- migrate:down
ALTER TABLE public.concerts
  DROP COLUMN calendar_first_failed_at,
  DROP COLUMN calendar_alerted_at,
  DROP COLUMN setlist_first_failed_at,
  DROP COLUMN setlist_alerted_at;
