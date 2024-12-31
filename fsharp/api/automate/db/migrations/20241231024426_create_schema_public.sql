-- migrate:up
CREATE SCHEMA IF NOT EXISTS public;

COMMENT ON SCHEMA public IS 'standard public schema';

-- migrate:down
DROP SCHEMA IF EXISTS public;
