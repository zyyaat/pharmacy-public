-- Migration: Single platform Super Admin bootstrap state
--
-- The first production Super Admin is created by the backend bootstrap using
-- a managed secret. This table records that the one-time bootstrap completed.
-- The unique index prevents a second Super Admin record at the database level.

CREATE TABLE IF NOT EXISTS platform_bootstrap_state (
    bootstrap_key VARCHAR(64) PRIMARY KEY,
    principal_id UUID NOT NULL REFERENCES company_users(id),
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT platform_bootstrap_state_singleton
        CHECK (bootstrap_key = 'super_admin')
);

DROP INDEX IF EXISTS company_users_single_active_super_admin;

CREATE UNIQUE INDEX IF NOT EXISTS company_users_single_super_admin
    ON company_users (role)
    WHERE role = 'super_admin';

CREATE OR REPLACE FUNCTION prevent_super_admin_identity_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.role = 'super_admin' AND (
        NEW.role IS DISTINCT FROM 'super_admin'::company_user_role
        OR NEW.deleted_at IS NOT NULL
        OR LOWER(NEW.email) IS DISTINCT FROM LOWER(OLD.email)
    ) THEN
        RAISE EXCEPTION
            'the platform Super Admin identity is immutable';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_super_admin_identity ON company_users;
CREATE TRIGGER protect_super_admin_identity
    BEFORE UPDATE ON company_users
    FOR EACH ROW
    EXECUTE FUNCTION prevent_super_admin_identity_change();