-- Migration: Label Templates Permission (barcode system v1 — Task 86)
-- Design: barcode-design-v2-review.md (§7.3, §7.4, §7.7 — Final Decision 13)
--
-- Adds the settings.labels permission gating the «الباركود والملصقات»
-- settings panel, following the exact pattern migration 20 established for
-- settings.receipts. Template DATA itself lives in pharmacies.settings JSONB
-- under the "labels" namespace (no schema change), like the receipt settings.

-- ============================================
-- 1) New permission
-- ============================================
INSERT INTO permissions (key, name, name_ar, description, module, category, is_system, sort_order) VALUES
    ('settings.labels', 'Label & Barcode Settings', 'إعدادات الملصقات والباركود', 'Can manage label templates and print barcode labels', 'settings', 'admin', true, 54)
ON CONFLICT (key) DO NOTHING;

UPDATE permissions SET name_ar = 'إعدادات الملصقات والباركود'
WHERE key = 'settings.labels' AND (name_ar IS NULL OR name_ar = '');

-- ============================================
-- 2) Role template grants (mirror the receipts pattern):
--    مدير الصيدلية (كل الصلاحيات) + صيدلي + أمين مخزن. Existing employees
--    WITHOUT explicit permission rows keep full access (migration 20 rule),
--    so adding rows here only shapes the templates and the catalog UI.
-- ============================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000001'::UUID, id
FROM permissions WHERE key = 'settings.labels'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000002'::UUID, id
FROM permissions WHERE key = 'settings.labels'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000004'::UUID, id
FROM permissions WHERE key = 'settings.labels'
ON CONFLICT (role_id, permission_id) DO NOTHING;
