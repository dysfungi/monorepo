-- migrate:up
GRANT ALL PRIVILEGES ON DATABASE automate_app TO automate_api;

-- migrate:down
REVOKE ALL PRIVILEGES ON DATABASE automate_app FROM automate_api;
