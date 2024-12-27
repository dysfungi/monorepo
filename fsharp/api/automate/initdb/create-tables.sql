CREATE OR REPLACE FUNCTION touch_updated_at_column()
RETURNS TRIGGER AS $BODY$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$BODY$ language 'plpgsql';


CREATE TABLE IF NOT EXISTS oauth_access
( id UUID PRIMARY KEY DEFAULT GEN_RANDOM_UUID()
, created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
, updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
, provider TEXT NOT NULL
, token_type TEXT NOT NULL
, access_token TEXT NOT NULL
, refresh_token TEXT
, expires_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
, account_id TEXT
);

CREATE TRIGGER touch_updated_at
BEFORE UPDATE ON oauth_access
FOR EACH ROW EXECUTE PROCEDURE touch_updated_at_column();
