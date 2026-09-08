-- Separate platform-admin and pharmacy authentication realms.
-- Existing sessions are intentionally invalidated so no legacy shared cookie
-- can cross the new boundary.

ALTER TABLE auth_sessions
    ADD COLUMN IF NOT EXISTS auth_realm VARCHAR(32);

UPDATE auth_sessions
SET auth_realm = 'pharmacy'
WHERE auth_realm IS NULL;

UPDATE auth_sessions
SET revoked_at = NOW()
WHERE revoked_at IS NULL;

ALTER TABLE auth_sessions
    ALTER COLUMN auth_realm SET NOT NULL,
    ALTER COLUMN auth_realm SET DEFAULT 'pharmacy';

ALTER TABLE auth_sessions
    DROP CONSTRAINT IF EXISTS auth_sessions_auth_realm_check;

ALTER TABLE auth_sessions
    ADD CONSTRAINT auth_sessions_auth_realm_check
    CHECK (auth_realm IN ('platform', 'pharmacy'));

CREATE INDEX IF NOT EXISTS idx_auth_sessions_realm
    ON auth_sessions (auth_realm, principal_type, principal_id)
    WHERE revoked_at IS NULL;