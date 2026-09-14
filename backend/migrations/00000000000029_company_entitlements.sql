-- Migration: company-level entitlement overrides («التحكم الكامل»)
--
-- Professional pattern (Stripe customer-specific prices, Chargebee custom
-- entitlements, Schematic/Stigg per-tenant overrides): the plan is the
-- COMPANY BASELINE; individual overrides merge ON TOP for one company
-- without forking the shared plan or touching every other subscriber.
--
-- Resolution order everywhere (enforcement AND presentation):
--     company override (unexpired)  →  plan set
--
-- Semantics per kind:
--   feature    — enabled = TRUE grants a module the plan lacks (e.g. give
--                one starter company the reports module for a month);
--                FALSE hides it even though the plan advertises it.
--   permission — enabled = TRUE grants an API permission; FALSE denies it.
--   limit      — value replaces the plan ceiling for that key
--                (-1 = unlimited; NULL is rejected by the CHECK below).
--
-- expires_at makes an override self-reversing (promotional grants, trial
-- extensions): expired rows are ignored at resolution time and stay on
-- disk as history. Every row carries an operator reason for the audit
-- trail surfaced on the company page.
--
-- This table is read by subscription.Service.loadSets and merged into the
-- cached EffectivePlan, so the pharmacy sidebar, the permission gate and
-- the limit gate all see ONE merged source of truth (lesson of the
-- plan_features/plan_permissions seed drift: display and enforcement must
-- never diverge).

CREATE TABLE IF NOT EXISTS company_entitlements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('feature', 'permission', 'limit')),
    key TEXT NOT NULL,
    -- feature/permission overrides: TRUE = grant, FALSE = deny, NULL = n/a.
    -- limit overrides: NULL here, value below instead.
    enabled BOOLEAN,
    -- limit overrides only; must be >= -1 (-1 = unlimited).
    value INT CHECK (kind <> 'limit' OR (value IS NOT NULL AND value >= -1)),
    reason TEXT,
    expires_at TIMESTAMPTZ,
-- bundle_key ties permission rows auto-inserted WITH a feature override to
-- that feature row (bundle_key = 'feature:<key>'), so the bundle is atomic:
-- deleting the feature override removes its bundled permission rows. This
-- prevents the Task-13 failure mode at account level: a feature granted in
-- the sidebar while its API keeps answering 403. NULL = operator-created row.
    bundle_key TEXT,
    created_by TEXT,
    created_by_email VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (company_id, kind, key)
);

CREATE INDEX IF NOT EXISTS idx_company_entitlements_company
    ON company_entitlements(company_id, kind, key);
