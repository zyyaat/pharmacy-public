-- Migration: platform audit log («سجلات المنصة»)
--
-- Defect found while building the per-company logs page: every platform
-- billing action (plan.create / plan.update / subscription.assign /
-- subscription.extend|cancel|suspend|reactivate / payment.manual /
-- payment.refund) called the TENANT writeAuditLog, which requires
-- principal.PharmacyID → "SELECT account_id FROM pharmacies WHERE id = ''"
-- matched no row → the insert failed → the error was swallowed by `_ =`.
-- Result: ZERO audit rows ever existed for platform billing actions, while
-- the platform dashboard pretended an activity feed existed.
--
-- The tenant audit_logs table cannot host these events anyway: its
-- pharmacy_id/account_id are NOT NULL by design (tenant RLS isolation).
-- Platform events belong in their own global, RLS-free table (house rule
-- from init.sql: "No RLS — admin access only"), with an optional
-- company_id column so the new per-company page can filter the log of ONE
-- account — the whole point of this task.

CREATE TABLE IF NOT EXISTS platform_audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id TEXT,
    actor_email VARCHAR(255),
    actor_display_name VARCHAR(255),
    actor_role VARCHAR(100),
    action VARCHAR(100) NOT NULL,
    action_category VARCHAR(50),
    entity_type VARCHAR(100) NOT NULL,
    entity_id TEXT,
    company_id UUID,              -- affected company when the event is per-account
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    changes_summary TEXT,
    severity VARCHAR(20) NOT NULL DEFAULT 'info',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_platform_audit_company
    ON platform_audit_logs(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_platform_audit_created
    ON platform_audit_logs(created_at DESC);
