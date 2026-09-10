-- Migration: Flexible Employee Permissions System (Task 42)
-- Goal: صلاحيات مرنة لكل موظف (تشغيل/إيقاف) + قوالب جاهزة لكل وظيفة
-- Safe rollout: employees with NO permission rows keep FULL access (legacy
-- behavior preserved). Restriction starts only after the owner saves an
-- explicit permission set for that employee.

-- ============================================
-- 1) FIX: trigger referenced increment_permission_version(uuid) which never
-- existed (only increment_employee_permission_version did). Any insert/update
-- on employee_permissions would fail at runtime. Provide the missing function.
-- ============================================
CREATE OR REPLACE FUNCTION increment_permission_version(p_employee_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_new_version INTEGER;
BEGIN
    UPDATE employees
    SET permission_version = permission_version + 1,
        updated_at = NOW()
    WHERE id = p_employee_id
    RETURNING permission_version INTO v_new_version;

    RETURN COALESCE(v_new_version, 0);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 1b) FIX: findEmployee() in the Go auth service selects employees.role but
-- the column never existed, so staff logins failed with invalid credentials.
-- Add the column with a sensible default.
-- ============================================
ALTER TABLE employees
    ADD COLUMN IF NOT EXISTS role VARCHAR(50) NOT NULL DEFAULT 'pharmacist';

-- ============================================
-- 2) granted_by must be nullable: the pharmacy owner is a company_user
-- principal (not an employees row) and must be able to grant permissions.
-- revoked_by was already nullable.
-- ============================================
ALTER TABLE employee_permissions ALTER COLUMN granted_by DROP NOT NULL;

-- ============================================
-- 3) Arabic labels for the permissions catalog (UI renders these directly)
-- ============================================
ALTER TABLE permissions ADD COLUMN IF NOT EXISTS name_ar VARCHAR(255);

UPDATE permissions SET name_ar = v.name_ar FROM (VALUES
    ('employees.view', 'عرض الموظفين'),
    ('employees.create', 'إضافة موظف جديد'),
    ('employees.update', 'تعديل بيانات الموظفين'),
    ('employees.delete', 'حذف الموظفين'),
    ('employees.manage_permissions', 'إدارة صلاحيات الموظفين'),
    ('inventory.view', 'عرض المخزون والأدوية'),
    ('inventory.adjust', 'تعديل كميات المخزون'),
    ('inventory.receive', 'استلام أصناف جديدة'),
    ('inventory.transfer', 'تحويل مخزون بين الفروع'),
    ('inventory.writeoff', 'إعدام مخزون (تالف/منتهي)'),
    ('inventory.manage_products', 'إضافة وتعديل المنتجات'),
    ('inventory.movements.view', 'عرض سجل حركات المخزون'),
    ('inventory.import', 'استيراد منتجات من ملف (ترحيل)'),
    ('products.global.manage', 'إدارة الكتالوج العام'),
    ('products.pharmacy.add', 'إضافة منتجات للصيدلية'),
    ('products.pharmacy.pricing', 'تحديد الأسعار'),
    ('branches.view', 'عرض الفروع'),
    ('branches.create', 'إضافة فروع'),
    ('branches.update', 'تعديل الفروع'),
    ('branches.delete', 'حذف الفروع'),
    ('reports.inventory', 'تقارير المخزون'),
    ('reports.sales', 'تقارير المبيعات'),
    ('reports.employees', 'تقارير الموظفين والحضور'),
    ('reports.financial', 'التقارير المالية'),
    ('reports.movements', 'تقرير حركات المخزون'),
    ('settings.general', 'الإعدادات العامة'),
    ('settings.billing', 'إعدادات الاشتراك والفواتير'),
    ('settings.integrations', 'إعدادات الربط الخارجي'),
    ('settings.receipts', 'إعدادات الفواتير والطباعة'),
    ('attendance.view', 'عرض الحضور والانصراف'),
    ('attendance.clock_in_out', 'تسجيل الحضور والانصراف'),
    ('attendance.manage', 'إدارة سجل الحضور'),
    ('pharmacy.admin', 'مدير الصيدلية (كل الصلاحيات)'),
    ('dashboard.view', 'لوحة التحكم'),
    ('pos.access', 'نقطة البيع (بيع وتعديل أسعار الكاشير)'),
    ('sales.view', 'سجل البيع والفواتير'),
    ('sales.returns', 'المرتجعات والاستبدال'),
    ('customers.view', 'عرض حسابات العملاء'),
    ('customers.create', 'إضافة عملاء'),
    ('customers.update', 'تعديل بيانات العملاء'),
    ('customers.delete', 'حذف العملاء'),
    ('customers.payments', 'تسجيل تحصيلات العملاء'),
    ('companies.view', 'عرض الشركات'),
    ('companies.create', 'إضافة شركات'),
    ('companies.update', 'تعديل الشركات'),
    ('companies.delete', 'حذف الشركات'),
    ('companies.manage_subscription', 'إدارة الاشتراكات'),
    ('company_users.view', 'عرض مستخدمي الشركة'),
    ('company_users.create', 'إضافة مستخدمي الشركة'),
    ('company_users.update', 'تعديل مستخدمي الشركة'),
    ('company_users.delete', 'حذف مستخدمي الشركة'),
    ('company_users.manage_permissions', 'إدارة صلاحيات مستخدمي الشركة'),
    ('accounts.view', 'عرض الحسابات'),
    ('accounts.create', 'إضافة حسابات'),
    ('accounts.update', 'تعديل الحسابات'),
    ('accounts.delete', 'حذف الحسابات'),
    ('platform.admin', 'إدارة المنصة'),
    ('platform.analytics', 'تحليلات المنصة'),
    ('platform.audit', 'سجل التدقيق')
) AS v(key, name_ar)
WHERE permissions.key = v.key;

-- ============================================
-- 4) New permissions for the real app modules
-- ============================================
INSERT INTO permissions (key, name, name_ar, description, module, category, is_system, sort_order) VALUES
    ('dashboard.view', 'View Dashboard', 'لوحة التحكم', 'Can open the pharmacy dashboard home', 'dashboard', 'read', true, 5),
    ('pos.access', 'Use Point of Sale', 'نقطة البيع (بيع وتعديل أسعار الكاشير)', 'Can open POS, search products and complete sales', 'pos', 'write', true, 21),
    ('sales.view', 'View Sales History', 'سجل البيع والفواتير', 'Can browse past invoices and their details', 'sales', 'read', true, 22),
    ('sales.returns', 'Process Returns', 'المرتجعات والاستبدال', 'Can create sale returns/replacements', 'sales', 'write', true, 23),
    ('customers.view', 'View Customers', 'عرض حسابات العملاء', 'Can view customer list, balances and statements', 'customers', 'read', true, 24),
    ('customers.create', 'Create Customers', 'إضافة عملاء', 'Can add new customers', 'customers', 'write', true, 25),
    ('customers.update', 'Update Customers', 'تعديل بيانات العملاء', 'Can edit customer information', 'customers', 'write', true, 26),
    ('customers.delete', 'Delete Customers', 'حذف العملاء', 'Can delete customers', 'customers', 'delete', true, 27),
    ('customers.payments', 'Record Customer Payments', 'تسجيل تحصيلات العملاء', 'Can record customer debt payments', 'customers', 'write', true, 28),
    ('inventory.movements.view', 'View Stock Movements', 'عرض سجل حركات المخزون', 'Can browse the stock movement ledger', 'inventory', 'read', true, 16),
    ('inventory.import', 'Import Products File', 'استيراد منتجات من ملف (ترحيل)', 'Can import products from spreadsheets (legacy migration)', 'inventory', 'admin', true, 17),
    ('reports.movements', 'Movements Report', 'تقرير حركات المخزون', 'Can view the stock movements report', 'reports', 'read', true, 44),
    ('settings.receipts', 'Receipt Settings', 'إعدادات الفواتير والطباعة', 'Can manage receipt and print settings', 'settings', 'admin', true, 53)
ON CONFLICT (key) DO NOTHING;

-- ============================================
-- 5) Arabic display for role templates
-- ============================================
ALTER TABLE roles ADD COLUMN IF NOT EXISTS display_name_ar VARCHAR(255);
ALTER TABLE roles ADD COLUMN IF NOT EXISTS description_ar TEXT;

UPDATE roles SET display_name_ar = v.name_ar, description_ar = v.description FROM (VALUES
    ('pharmacy_admin', 'مدير الصيدلية', 'كل الصلاحيات — يدير الموظفين والصلاحيات والإعدادات'),
    ('pharmacist', 'صيدلي', 'بيع واستلام وتعديل مخزون مع تقارير أساسية'),
    ('cashier', 'كاشير', 'بيع على نقطة البيع وعرض المخزون فقط'),
    ('inventory_manager', 'أمين مخزن', 'إدارة كاملة للمخزون والاستلام والجرد والتقارير'),
    ('hr_manager', 'مسؤول الموظفين', 'إدارة الموظفين والحضور وتقاريرهم'),
    ('accountant', 'محاسب', 'متابعة المبيعات والتحصيلات والتقارير المالية')
) AS v(name, name_ar, description)
WHERE roles.name = v.name;

-- New template: محاسب (accountant)
INSERT INTO roles (id, name, display_name, display_name_ar, description, description_ar, is_system, is_default, sort_order)
VALUES ('00000000-0000-0000-0000-000000000006', 'accountant', 'Accountant / محاسب', 'محاسب',
        'Follows sales, customer collections and financial reports',
        'متابعة المبيعات والتحصيلات والتقارير المالية', true, false, 6)
ON CONFLICT (name) DO NOTHING;

-- ============================================
-- 6) Refresh template permission sets (idempotent rewrite)
-- ============================================
DELETE FROM role_permissions;

-- مدير الصيدلية: كل شيء ما عدا إدارة الكتالوج العام (منصّة)
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000001'::UUID, id
FROM permissions WHERE key != 'products.global.manage';

-- صيدلي
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000002'::UUID, id
FROM permissions WHERE key = ANY(ARRAY[
    'dashboard.view', 'pos.access', 'sales.view', 'sales.returns',
    'inventory.view', 'inventory.adjust', 'inventory.receive', 'inventory.manage_products',
    'products.pharmacy.add', 'products.pharmacy.pricing',
    'customers.view', 'customers.create', 'customers.payments',
    'branches.view', 'reports.inventory', 'reports.sales',
    'attendance.view', 'attendance.clock_in_out', 'settings.receipts'
]);

-- كاشير
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000003'::UUID, id
FROM permissions WHERE key = ANY(ARRAY[
    'dashboard.view', 'pos.access', 'sales.view',
    'inventory.view', 'customers.view', 'customers.create',
    'branches.view', 'attendance.clock_in_out', 'settings.receipts'
]);

-- أمين مخزن
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000004'::UUID, id
FROM permissions WHERE key = ANY(ARRAY[
    'dashboard.view', 'inventory.view', 'inventory.adjust', 'inventory.receive',
    'inventory.transfer', 'inventory.writeoff', 'inventory.manage_products',
    'inventory.movements.view', 'inventory.import',
    'products.pharmacy.add', 'products.pharmacy.pricing',
    'branches.view', 'reports.inventory', 'reports.movements',
    'attendance.clock_in_out'
]);

-- مسؤول الموظفين
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000005'::UUID, id
FROM permissions WHERE key = ANY(ARRAY[
    'dashboard.view', 'employees.view', 'employees.create', 'employees.update',
    'employees.manage_permissions', 'attendance.view', 'attendance.manage',
    'reports.employees', 'branches.view'
]);

-- محاسب
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000006'::UUID, id
FROM permissions WHERE key = ANY(ARRAY[
    'dashboard.view', 'sales.view', 'customers.view', 'customers.payments',
    'reports.sales', 'reports.financial', 'reports.inventory', 'branches.view',
    'attendance.view'
]);
