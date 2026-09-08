-- Migration: Publish-compatible views
--
-- Replit's development-to-production database copy creates placeholder views
-- before restoring custom enum types. Keep view output stable for the API while
-- avoiding enum references in those placeholder definitions.

-- ------------------------------------------------------------------
-- Legacy schema reconciliation (idempotent).
--
-- Some databases carry a partial copy of an earlier schema that predates
-- one or more ALTER statements from holding_company.sql (most notably
-- accounts.deleted_at). The views below reference those columns, so make
-- sure they exist before creating anything. Every statement is additive
-- (ADD COLUMN IF NOT EXISTS, no NOT NULL / UNIQUE enforcement) and safe
-- to run repeatedly; on an up-to-date database they are all no-ops.
-- ------------------------------------------------------------------

ALTER TABLE accounts
    ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id) ON DELETE SET NULL;
ALTER TABLE accounts
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS name_ar VARCHAR(255);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS legal_name VARCHAR(255);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS registration_number VARCHAR(100);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS website VARCHAR(255);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS address_line1 VARCHAR(255);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS address_line2 VARCHAR(255);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS city VARCHAR(100);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS state_province VARCHAR(100);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS postal_code VARCHAR(20);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS country VARCHAR(100) DEFAULT 'EG';
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS status company_status DEFAULT 'trial';
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS plan company_plan DEFAULT 'free';
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ;
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS subscription_current_period_start TIMESTAMPTZ;
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS subscription_current_period_end TIMESTAMPTZ;
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS max_accounts INTEGER DEFAULT 1;
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS max_users_per_account INTEGER DEFAULT 10;
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS default_currency VARCHAR(10) DEFAULT 'EGP';
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS timezone VARCHAR(100) DEFAULT 'Africa/Cairo';
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS locale VARCHAR(10) DEFAULT 'ar-EG';
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS settings JSONB DEFAULT '{}';
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS logo_url TEXT;
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS primary_color VARCHAR(7);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS secondary_color VARCHAR(7);
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN GENERATED ALWAYS AS (deleted_at IS NULL) STORED;

ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS login_attempts INTEGER DEFAULT 0;
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN DEFAULT false;
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS display_name VARCHAR(200);
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS phone VARCHAR(50);
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS permission_version INTEGER DEFAULT 0;
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS email_verification_token VARCHAR(255);
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS password_reset_token VARCHAR(255);
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMPTZ;
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS preferences JSONB DEFAULT '{}';
ALTER TABLE company_users
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE pharmacies
    ADD COLUMN IF NOT EXISTS country VARCHAR(100);
ALTER TABLE pharmacies
    ADD COLUMN IF NOT EXISTS is_main_branch BOOLEAN DEFAULT true;
ALTER TABLE pharmacies
    ADD COLUMN IF NOT EXISTS default_branch_id UUID;
ALTER TABLE pharmacies
    ADD COLUMN IF NOT EXISTS currency currency_code;

ALTER TABLE branches
    ADD COLUMN IF NOT EXISTS code VARCHAR(50);
ALTER TABLE branches
    ADD COLUMN IF NOT EXISTS country VARCHAR(100);

DROP VIEW IF EXISTS current_inventory;
DROP VIEW IF EXISTS v_company_summary;
DROP VIEW IF EXISTS v_company_user_with_permissions;

CREATE VIEW current_inventory AS
SELECT
    ib.id AS batch_id,
    pp.id AS pharmacy_product_id,
    pp.pharmacy_id,
    ib.branch_id,
    gp.id AS global_product_id,
    gp.name AS product_name,
    gp.generic_name,
    gp.brand_name,
    gp.barcode,
    gp.dosage_form::text AS dosage_form,
    gp.strength,
    ib.batch_number,
    ib.unit::text AS unit,
    calculate_batch_current_stock(ib.id) AS quantity,
    ib.cost_per_unit,
    ib.total_cost,
    ib.expiry_date,
    ib.days_until_expiry,
    pp.selling_price,
    pp.min_stock_level,
    b.name AS branch_name,
    CASE
        WHEN calculate_batch_current_stock(ib.id) <= pp.min_stock_level THEN 'low_stock'
        WHEN ib.expiry_date IS NOT NULL
            AND ib.expiry_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'expiring_soon'
        WHEN ib.is_quarantined THEN 'quarantined'
        ELSE 'normal'
    END AS status
FROM inventory_batches ib
JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
JOIN global_products gp ON pp.global_product_id = gp.id
LEFT JOIN branches b ON ib.branch_id = b.id
WHERE ib.quantity > 0 OR calculate_batch_current_stock(ib.id) > 0;

COMMENT ON VIEW current_inventory IS
    'Pre-calculated view of current inventory - use for dashboards and reports';
COMMENT ON COLUMN current_inventory.quantity IS
    'Calculated from SUM(stock_movements) - always accurate';

CREATE VIEW v_company_summary AS
SELECT
    c.id,
    c.name,
    c.name_ar,
    c.legal_name,
    c.registration_number,
    c.email,
    c.phone,
    c.website,
    c.address_line1,
    c.address_line2,
    c.city,
    c.state_province,
    c.postal_code,
    c.country,
    c.status::text AS status,
    c.plan::text AS plan,
    c.trial_ends_at,
    c.subscription_current_period_start,
    c.subscription_current_period_end,
    c.max_accounts,
    c.max_users_per_account,
    c.default_currency,
    c.timezone,
    c.locale,
    c.settings,
    c.logo_url,
    c.primary_color,
    c.secondary_color,
    c.created_at,
    c.updated_at,
    c.deleted_at,
    c.is_active,
    COUNT(DISTINCT a.id) AS total_accounts,
    COUNT(DISTINCT CASE
        WHEN a.status::text = 'active' THEN a.id
    END) AS active_accounts,
    COUNT(DISTINCT cu.id) AS total_users
FROM companies c
LEFT JOIN accounts a
    ON a.company_id = c.id AND a.deleted_at IS NULL
LEFT JOIN company_users cu
    ON cu.company_id = c.id
    AND cu.deleted_at IS NULL
    AND cu.is_active = true
WHERE c.deleted_at IS NULL
GROUP BY c.id;

COMMENT ON VIEW v_company_summary IS
    'Company overview with account/user counts';

CREATE VIEW v_company_user_with_permissions AS
SELECT
    cu.id,
    cu.company_id,
    cu.email,
    cu.password_hash,
    cu.last_login_at,
    cu.login_attempts,
    cu.locked_until,
    cu.password_changed_at,
    cu.must_change_password,
    cu.first_name,
    cu.last_name,
    cu.display_name,
    cu.avatar_url,
    cu.phone,
    cu.role::text AS role,
    cu.permission_version,
    cu.is_active,
    cu.email_verified_at,
    cu.email_verification_token,
    cu.password_reset_token,
    cu.password_reset_expires_at,
    cu.preferences,
    cu.created_at,
    cu.updated_at,
    cu.deleted_at,
    COALESCE(perm_count.permission_count, 0) AS total_permissions,
    ARRAY(
        SELECT p.key
        FROM company_user_permissions cup2
        JOIN permissions p ON cup2.permission_id = p.id
        WHERE cup2.company_user_id = cu.id
          AND cup2.is_active = true
    ) AS permission_keys
FROM company_users cu
LEFT JOIN (
    SELECT company_user_id, COUNT(*) AS permission_count
    FROM company_user_permissions
    WHERE is_active = true
    GROUP BY company_user_id
) perm_count ON perm_count.company_user_id = cu.id
WHERE cu.deleted_at IS NULL;

COMMENT ON VIEW v_company_user_with_permissions IS
    'Company users with their permission details';