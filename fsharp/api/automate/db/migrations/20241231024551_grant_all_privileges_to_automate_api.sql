-- migrate:up
GRANT ALL PRIVILEGES
  ON DATABASE automate_app
  TO automate_api;

ALTER DEFAULT PRIVILEGES
  IN SCHEMA public
  GRANT ALL PRIVILEGES
  ON TABLES
  TO automate_api;

-- migrate:down
ALTER DEFAULT PRIVILEGES
  IN SCHEMA public
  REVOKE ALL PRIVILEGES
  ON TABLES
  FROM automate_api;

REVOKE ALL PRIVILEGES
  ON DATABASE automate_app
  FROM automate_api;
