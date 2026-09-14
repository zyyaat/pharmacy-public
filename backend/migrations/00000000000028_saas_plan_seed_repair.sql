-- Migration: SaaS plan seed repair («نشط لكن الصلاحيات متوقفة»)
--
-- Root cause (found by the full-file audit): migration 26 seeded the
-- free/starter plan_permissions by joining plan_features BEFORE the
-- plan_features INSERT that populates it (statement order inside the
-- file). On every database where 26 ran in file order, free and starter
-- hold ONLY the 12-key core set and NONE of the feature-derived business
-- permissions — pos, sales, inventory, customers. A company assigned to
-- «البداية» (starter) therefore shows a perfectly ACTIVE subscription in
-- every list while every module API answers 403 plan_permission_denied:
-- the status gate passes, the permission set is empty. The two plan
-- tables (plan_features = presentation, plan_permissions = enforcement)
-- diverged at seed time and the UI showed the optimistic half.
--
-- Repair, scoped strictly to the seed defect:
--   * re-insert the core set (same statement as 26 — covers any database
--     that lost core rows for any reason), then
--   * re-derive feature permissions for free/starter from
--     plan_features × feature_permissions (now that plan_features exists).
--
-- Guarantees:
--   * idempotent: ON CONFLICT DO NOTHING — replaying is a no-op;
--   * strictly additive: it can only ADD what the original seed intended.
--     It can never remove or weaken an intentional super-admin
--     customization made through the plan editor;
--   * professional/enterprise are intentionally untouched (their grant is
--     "everything except the platform realm" and is already complete).
--
-- Future drift of ANY plan is not silently mutated here — the startup
-- consistency guard in RunMigrations logs it loudly instead, so the
-- correction stays a human/audited decision (house policy: enforcement
-- data changes go through migrations, detection is automatic).

-- 1. Core set (every plan) — same keys as migration 26 §7
INSERT INTO plan_permissions (plan_id, permission_id)
SELECT pl.id, p.id
FROM plans pl
JOIN permissions p ON p.key = ANY(ARRAY[
    'dashboard.view', 'settings.general', 'settings.receipts',
    'settings.labels', 'settings.billing', 'settings.integrations',
    'companies.view', 'companies.update',
    'company_users.view', 'company_users.create', 'company_users.update',
    'accounts.view'
])
WHERE pl.slug IN ('free', 'starter')
ON CONFLICT (plan_id, permission_id) DO NOTHING;

-- 2. Feature-derived set for free/starter — the block that silently
--    inserted zero rows in migration 26 because plan_features was empty
--    at that moment.
INSERT INTO plan_permissions (plan_id, permission_id)
SELECT pl.id, fp.permission_id
FROM plans pl
JOIN plan_features pf ON pf.plan_id = pl.id
JOIN feature_permissions fp ON fp.feature_key = pf.feature_key
WHERE pl.slug IN ('free', 'starter')
ON CONFLICT (plan_id, permission_id) DO NOTHING;
