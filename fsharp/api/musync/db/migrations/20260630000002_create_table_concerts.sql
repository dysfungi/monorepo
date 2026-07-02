-- migrate:up
CREATE SCHEMA IF NOT EXISTS public;
COMMENT ON SCHEMA public IS 'standard public schema';

-- Auto-touch updated_at on every UPDATE (shared trigger function).
CREATE OR REPLACE FUNCTION public.touch_updated_at_column ()
RETURNS TRIGGER AS $BODY$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$BODY$ language 'plpgsql';

-- One row per "Going" concert. Column groups mirror the F# Concert aggregate
-- (identity / show / calendar / setlist / timestamps). Nullable columns are
-- the F# `option` fields; `probable_setlist` holds the serialized ProbableSetlist.
CREATE TABLE IF NOT EXISTS public.concerts
( id                            uuid        NOT NULL    DEFAULT gen_random_uuid()
-- identity
, account_id                    text        NOT NULL    DEFAULT 'default'
, songkick_uid                  text        NOT NULL
-- show
, artist                        text        NOT NULL
, venue                         text        NOT NULL
, city                          text        NOT NULL
, country                       text        NOT NULL
, starts_at                     timestamptz NOT NULL
, tz                            text        NOT NULL
, plan_status                   text        NOT NULL    DEFAULT 'going'
-- calendar
, calendar_uid                  text
, content_hash                  text
, calendar_sequence             int         NOT NULL    DEFAULT 0
, calendar_sent_at              timestamptz             DEFAULT NULL
, calendar_attempts             int         NOT NULL    DEFAULT 0
, calendar_last_error           text
-- setlist
, probable_setlist              jsonb
, probable_setlist_computed_at  timestamptz             DEFAULT NULL
, setlist_notified_at           timestamptz             DEFAULT NULL
, setlist_found_at              timestamptz             DEFAULT NULL
, setlist_attempts              int         NOT NULL    DEFAULT 0
, setlist_last_error            text
-- timestamps
, created_at                    timestamptz NOT NULL    DEFAULT now()
, updated_at                    timestamptz NOT NULL    DEFAULT now()
, PRIMARY KEY (id)
, UNIQUE (songkick_uid)
);

CREATE OR REPLACE TRIGGER touch_updated_at
BEFORE UPDATE ON public.concerts
FOR EACH ROW EXECUTE FUNCTION touch_updated_at_column();

-- migrate:down
DROP TRIGGER IF EXISTS touch_updated_at ON public.concerts;

DROP TABLE IF EXISTS public.concerts;

DROP FUNCTION IF EXISTS public.touch_updated_at_column;
