-- migrate:up
-- Songkick concert-page enrichment (doors/show/openers/ticket vendor), scraped
-- from the page's schema.org MusicEvent JSON-LD. `songkick_event_url` arrives in
-- the ICS feed (a normal upsert column). The rest are populated out-of-band by the
-- enrich step and are NOT in the feed, so the upsert preserves them across
-- re-ingest and resets them to NULL only when the show instant changes (a
-- reschedule) — see Persistence.upsert.
ALTER TABLE public.concerts
  ADD COLUMN songkick_event_url text,
  ADD COLUMN event_start_at      timestamptz,
  ADD COLUMN doors_at            timestamptz,
  ADD COLUMN show_at             timestamptz,
  ADD COLUMN openers             text,
  ADD COLUMN ticket_vendor       text,
  ADD COLUMN ticket_url          text,
  ADD COLUMN enriched_at         timestamptz;

-- migrate:down
ALTER TABLE public.concerts
  DROP COLUMN songkick_event_url,
  DROP COLUMN event_start_at,
  DROP COLUMN doors_at,
  DROP COLUMN show_at,
  DROP COLUMN openers,
  DROP COLUMN ticket_vendor,
  DROP COLUMN ticket_url,
  DROP COLUMN enriched_at;
