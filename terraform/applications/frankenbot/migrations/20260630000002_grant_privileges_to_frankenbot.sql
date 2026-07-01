-- migrate:up
-- Run by the admin role (the dbmate secret). Grants the least-privilege
-- frankenbot login role access to its database, and — crucially — sets DEFAULT
-- PRIVILEGES so tables created by LATER migrations (owned by admin) are
-- automatically usable by the frankenbot role the dispatcher connects as.
-- Mirrors automate's grant migration; ordering matters (this precedes the table
-- creation in the next migration).
GRANT ALL PRIVILEGES
  ON DATABASE frankenbot
  TO frankenbot;

ALTER DEFAULT PRIVILEGES
  IN SCHEMA public
  GRANT ALL PRIVILEGES
  ON TABLES
  TO frankenbot;

-- migrate:down
ALTER DEFAULT PRIVILEGES
  IN SCHEMA public
  REVOKE ALL PRIVILEGES
  ON TABLES
  FROM frankenbot;

REVOKE ALL PRIVILEGES
  ON DATABASE frankenbot
  FROM frankenbot;
