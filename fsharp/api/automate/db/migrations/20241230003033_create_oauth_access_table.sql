-- migrate:up
CREATE SCHEMA IF NOT EXISTS public;
COMMENT ON SCHEMA public IS 'standard public schema';

CREATE OR REPLACE FUNCTION public.touch_updated_at_column ()
RETURNS TRIGGER AS $BODY$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$BODY$ language 'plpgsql';

CREATE TABLE IF NOT EXISTS public.oauth_access
( id                uuid        NOT NULL    DEFAULT gen_random_uuid()
, created_at        timestamptz NOT NULL    DEFAULT now()
, updated_at        timestamptz NOT NULL    DEFAULT now()
, account_id        text        NOT NULL
, provider          text        NOT NULL
, token_type        text        NOT NULL
, access_token      text        NOT NULL
, refresh_token     text
, expires_at        timestamptz             DEFAULT NULL
, PRIMARY KEY (id)
, UNIQUE (account_id, provider)
);

CREATE OR REPLACE TRIGGER touch_updated_at
BEFORE UPDATE ON public.oauth_access
FOR EACH ROW EXECUTE FUNCTION touch_updated_at_column();

-- migrate:down
DROP TRIGGER IF EXISTS touch_updated_at ON public.oauth_access;
DROP TABLE IF EXISTS public.oauth_access;
DROP FUNCTION IF EXISTS public.touch_updated_at_column;
