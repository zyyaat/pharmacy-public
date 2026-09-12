-- Migration: SaaS Plans & Subscriptions (fully dynamic plans system)
--
-- Pharmacy OS becomes a plan-driven SaaS: the super admin creates plans
-- (name, pricing, features, permissions, limits) from the admin dashboard
-- with zero code changes, and every company's capabilities are bounded by
-- its subscription's plan — ON TOP of the existing per-user RBAC:
--
--   Allow = plan_permissions ∋ key  AND  user_permissions ∋ key
--
-- Design invariants (architecture decision, Task 90):
--   * plans are DATA, never code: no `if plan == "pro"` anywhere —
--     enforcement only asks "does the plan include permission X?" and
--     "is current usage below limit Y?".
--   * Features are a presentation/grouping layer (pricing page, sidebar);
--     plan_permissions is the enforcement source of truth.
--     feature_permissions is an editor convenience mapping so toggling a
--     feature pre-selects its permission keys.
--   * Limits are dynamic key/value pairs (-1 = unlimited). Known keys today:
--     branches, users (company_users), employees (pharmacy staff), products.
--   * One LIVE subscription per company (trial|active|pending) enforced by
--     a partial unique index. Expired/cancelled/suspended rows are history.
--   * payments + payment_transactions exist from day one so the Paymob
--     integration (later phase) only adds code, never schema.
--   * Backfill: every existing company gets a subscription — active
--     companies are grandfathered on 'enterprise' (zero disruption),
--     running trials keep their trial on 'professional' (the full-
--     experience default). companies.plan is re-synced for display.
--
-- All statements are guarded (IF NOT EXISTS / ON CONFLICT) so replaying the
-- migration is a no-op, matching the house migration style.

-- ---------------------------------------------------------------------------
-- 1. features — the presentation catalog (what a plan can advertise)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS features (
    key          VARCHAR(50) PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    name_ar      VARCHAR(100),
    description  TEXT,
    sort_order   INT NOT NULL DEFAULT 0,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO features (key, name, name_ar, sort_order) VALUES
    ('pos',          'Point of Sale',      'نقطة البيع',          1),
    ('sales',        'Sales & Invoices',   'المبيعات والفواتير',   2),
    ('inventory',    'Inventory',          'المخزون والأدوية',     3),
    ('customers',    'Customers',          'حسابات العملاء',       4),
    ('employees',    'Employees',          'الموظفون',             5),
    ('attendance',   'Attendance',         'الحضور والانصراف',     6),
    ('branches',     'Branches',           'إدارة الفروع',         7),
    ('reports',      'Reports',            'التقارير',             8),
    ('multi_branch', 'Multi Branch',       'فروع متعددة',          9)
ON CONFLICT (key) DO NOTHING;

DROP TRIGGER IF EXISTS update_features_updated_at ON features;
CREATE TRIGGER update_features_updated_at BEFORE UPDATE ON features
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ---------------------------------------------------------------------------
-- 2. plans — dynamic plan definitions (money in integer piastres, migration 14)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS plans (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug                    VARCHAR(50) NOT NULL UNIQUE,
    name                    VARCHAR(100) NOT NULL,
    name_ar                 VARCHAR(100),
    description             TEXT,
    monthly_price_piastres  BIGINT NOT NULL DEFAULT 0
                            CHECK (monthly_price_piastres >= 0),
    yearly_price_piastres   BIGINT NOT NULL DEFAULT 0
                            CHECK (yearly_price_piastres >= 0),
    currency                CHAR(3) NOT NULL DEFAULT 'EGP',
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    is_public               BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order              INT NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS update_plans_updated_at ON plans;
CREATE TRIGGER update_plans_updated_at BEFORE UPDATE ON plans
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ---------------------------------------------------------------------------
-- 3. plan_features / 4. plan_permissions / 5. plan_limits
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS plan_features (
    plan_id     UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
    feature_key VARCHAR(50) NOT NULL REFERENCES features(key) ON DELETE CASCADE,
    PRIMARY KEY (plan_id, feature_key)
);

CREATE TABLE IF NOT EXISTS plan_permissions (
    plan_id       UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (plan_id, permission_id)
);

CREATE TABLE IF NOT EXISTS plan_limits (
    plan_id   UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
    limit_key VARCHAR(50) NOT NULL,
    value     INT NOT NULL CHECK (value > 0 OR value = -1),
    PRIMARY KEY (plan_id, limit_key)
);

COMMENT ON COLUMN plan_limits.value IS
    'Usage ceiling for limit_key (-1 = unlimited). Known keys: branches, users (company_users), employees (pharmacy staff), products (pharmacy_products).';

-- ---------------------------------------------------------------------------
-- 6. feature_permissions — editor convenience: which permission keys a
--    feature suggests when toggled in the plan editor. plan_permissions
--    remains the enforcement source of truth.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feature_permissions (
    feature_key   VARCHAR(50) NOT NULL REFERENCES features(key) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (feature_key, permission_id)
);

INSERT INTO feature_permissions (feature_key, permission_id)
SELECT m.feature_key, p.id
FROM (VALUES
    ('pos',        'pos.access'),
    ('sales',      'sales.view'), ('sales', 'sales.returns'),
    ('inventory',  'inventory.view'), ('inventory', 'inventory.adjust'),
    ('inventory',  'inventory.receive'), ('inventory', 'inventory.transfer'),
    ('inventory',  'inventory.writeoff'), ('inventory', 'inventory.manage_products'),
    ('inventory',  'inventory.movements.view'), ('inventory', 'inventory.import'),
    ('inventory',  'products.pharmacy.add'), ('inventory', 'products.pharmacy.pricing'),
    ('customers',  'customers.view'), ('customers', 'customers.create'),
    ('customers',  'customers.update'), ('customers', 'customers.delete'),
    ('customers',  'customers.payments'),
    ('employees',  'employees.view'), ('employees', 'employees.create'),
    ('employees',  'employees.update'), ('employees', 'employees.delete'),
    ('employees',  'employees.manage_permissions'),
    ('attendance', 'attendance.view'), ('attendance', 'attendance.clock_in_out'),
    ('attendance', 'attendance.manage'),
    ('branches',   'branches.view'), ('branches', 'branches.create'),
    ('branches',   'branches.update'), ('branches', 'branches.delete'),
    ('reports',    'reports.inventory'), ('reports', 'reports.sales'),
    ('reports',    'reports.employees'), ('reports', 'reports.financial'),
    ('reports',    'reports.movements')
) AS m(feature_key, perm_key)
JOIN permissions p ON p.key = m.perm_key
ON CONFLICT (feature_key, permission_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 7. Seed plans. Core permissions (company management + settings) are part
--    of EVERY plan — plans gate the business modules, never the owner's
--    ability to run his company or see his billing page.
-- ---------------------------------------------------------------------------
INSERT INTO plans (id, slug, name, name_ar, description,
                   monthly_price_piastres, yearly_price_piastres, sort_order)
VALUES
    (uuid_generate_v4(), 'free',         'Free',         'المجانية',
     'Core pharmacy management to get started', 0, 0, 1),
    (uuid_generate_v4(), 'starter',      'Starter',      'البداية',
     'Selling and inventory essentials for one branch', 30000, 300000, 2),
    (uuid_generate_v4(), 'professional', 'Professional', 'الاحترافية',
     'Everything a growing pharmacy needs: multi-branch, staff, reports',
     50000, 500000, 3),
    (uuid_generate_v4(), 'enterprise',   'Enterprise',   'المؤسسات',
     'Unlimited scale with every module enabled', 100000, 1000000, 4)
ON CONFLICT (slug) DO NOTHING;

-- Core set granted to every plan (idempotent re-run safe)
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
ON CONFLICT (plan_id, permission_id) DO NOTHING;

-- free & starter: their enabled features' permission sets
INSERT INTO plan_permissions (plan_id, permission_id)
SELECT pl.id, fp.permission_id
FROM plans pl
JOIN plan_features pf ON pf.plan_id = pl.id
JOIN feature_permissions fp ON fp.feature_key = pf.feature_key
WHERE pl.slug IN ('free', 'starter')
ON CONFLICT (plan_id, permission_id) DO NOTHING;

INSERT INTO plan_features (plan_id, feature_key)
SELECT pl.id, f.key
FROM plans pl
JOIN features f ON f.key = ANY( CASE pl.slug
    WHEN 'free'    THEN ARRAY['pos','sales','inventory','customers']
    WHEN 'starter' THEN ARRAY['pos','sales','inventory','customers']
    ELSE ARRAY['pos','sales','inventory','customers','employees',
               'attendance','branches','reports','multi_branch'] END::text[])
WHERE pl.slug IN ('free','starter','professional','enterprise')
ON CONFLICT (plan_id, feature_key) DO NOTHING;

-- professional & enterprise: every permission except the platform realm
-- (super-admin only) and the pharmacy.admin master key — a plan must never
-- silently hand out the RBAC bypass key; user-level grants decide that.
INSERT INTO plan_permissions (plan_id, permission_id)
SELECT pl.id, p.id
FROM plans pl
JOIN permissions p ON TRUE
WHERE pl.slug IN ('professional','enterprise')
  AND p.key NOT IN ('platform.admin','platform.analytics','platform.audit',
                    'pharmacy.admin')
ON CONFLICT (plan_id, permission_id) DO NOTHING;

INSERT INTO plan_limits (plan_id, limit_key, value)
SELECT pl.id, l.limit_key, l.value
FROM plans pl
JOIN (VALUES
    ('free',         'branches', 1),
    ('free',         'users',    2),
    ('free',         'employees', 1),
    ('free',         'products', 100),
    ('starter',      'branches', 1),
    ('starter',      'users',    3),
    ('starter',      'employees', 5),
    ('starter',      'products', 5000),
    ('professional', 'branches', 5),
    ('professional', 'users',    20),
    ('professional', 'employees', 50),
    ('professional', 'products', 50000),
    ('enterprise',   'branches', -1),
    ('enterprise',   'users',    -1),
    ('enterprise',   'employees', -1),
    ('enterprise',   'products', -1)
) AS l(slug, limit_key, value) ON l.slug = pl.slug
ON CONFLICT (plan_id, limit_key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 8. subscriptions — one live row per company (partial unique index)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscriptions (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id           UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    plan_id              UUID NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
    status               VARCHAR(20) NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('trial','active','expired',
                                           'cancelled','suspended','pending')),
    billing_interval     VARCHAR(10) NOT NULL DEFAULT 'none'
                         CHECK (billing_interval IN ('monthly','yearly','none')),
    current_period_start TIMESTAMPTZ,
    current_period_end   TIMESTAMPTZ,
    trial_ends_at        TIMESTAMPTZ,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    source               VARCHAR(20) NOT NULL DEFAULT 'manual'
                         CHECK (source IN ('registration','payment','manual',
                                           'migration')),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One live subscription per company: trial/active/pending are mutually
-- exclusive states; expired/cancelled/suspended are terminal history.
CREATE UNIQUE INDEX IF NOT EXISTS one_live_subscription_per_company
    ON subscriptions(company_id)
    WHERE status IN ('pending','trial','active');

CREATE INDEX IF NOT EXISTS idx_subscriptions_company
    ON subscriptions(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status
    ON subscriptions(status);

DROP TRIGGER IF EXISTS update_subscriptions_updated_at ON subscriptions;
CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE subscriptions IS
    'Billing lifecycle per company. The backend evaluates status lazily (trial_ends_at / current_period_end vs NOW()) so correctness never depends on a scheduler; the stored status is flipped on first access after a deadline passes.';

-- ---------------------------------------------------------------------------
-- 9. payments + payment_transactions — Paymob-ready from day one (the
--    provider only ever writes rows; the webhook is the sole activator).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
    id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id         UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subscription_id    UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    plan_id            UUID NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
    billing_interval   VARCHAR(10) NOT NULL
                       CHECK (billing_interval IN ('monthly','yearly')),
    amount_piastres    BIGINT NOT NULL CHECK (amount_piastres >= 0),
    currency           CHAR(3) NOT NULL DEFAULT 'EGP',
    provider           VARCHAR(30) NOT NULL DEFAULT 'paymob',
    provider_reference VARCHAR(100),
    status             VARCHAR(20) NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','succeeded','failed',
                                         'refunded','voided','cancelled')),
    metadata           JSONB,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_company
    ON payments(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_reference
    ON payments(provider, provider_reference);

DROP TRIGGER IF EXISTS update_payments_updated_at ON payments;
CREATE TRIGGER update_payments_updated_at BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE IF NOT EXISTS payment_transactions (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id              UUID NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    txn_type                VARCHAR(20) NOT NULL
                            CHECK (txn_type IN ('intent','webhook','refund','void')),
    provider_transaction_id VARCHAR(100),
    amount_piastres         BIGINT,
    hmac_verified           BOOLEAN NOT NULL DEFAULT FALSE,
    payload                 JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_transactions_payment
    ON payment_transactions(payment_id, created_at DESC);

COMMENT ON TABLE payments IS
    'One row per payment attempt (Paymob intention or manual registration). The subscription is only ever activated/extended from a succeeded payment processed server-side — never from the frontend.';

-- ---------------------------------------------------------------------------
-- 10. Backfill — every existing company gets a subscription (zero
--     disruption): running trials continue as trials on 'professional',
--     everything else is grandfathered active on 'enterprise' with no
--     expiry until the super admin decides otherwise.
-- ---------------------------------------------------------------------------
INSERT INTO subscriptions
    (company_id, plan_id, status, billing_interval, trial_ends_at,
     current_period_start, source)
SELECT c.id,
       CASE WHEN c.status = 'trial' AND c.trial_ends_at IS NOT NULL
                 AND c.trial_ends_at > NOW()
            THEN tp.id ELSE ep.id END,
       CASE WHEN c.status = 'trial' AND c.trial_ends_at IS NOT NULL
                 AND c.trial_ends_at > NOW()
            THEN 'trial' ELSE 'active' END,
       'none',
       CASE WHEN c.status = 'trial' AND c.trial_ends_at IS NOT NULL
                 AND c.trial_ends_at > NOW()
            THEN c.trial_ends_at END,
       NOW(),
       'migration'
FROM companies c
JOIN plans tp ON tp.slug = 'professional'
JOIN plans ep ON ep.slug = 'enterprise'
WHERE c.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM subscriptions s
      WHERE s.company_id = c.id AND s.status IN ('trial','active')
  );

-- Keep the legacy display column in sync with the backfilled reality
UPDATE companies c
SET plan = p.slug::company_plan
FROM subscriptions s
JOIN plans p ON p.id = s.plan_id
WHERE s.company_id = c.id AND s.status IN ('trial','active')
  AND c.plan::text <> p.slug;

-- ---------------------------------------------------------------------------
-- 11. Trial settings — duration stays super-admin editable (existing key),
--     plus the default trial plan slug (full-experience trial decision).
-- ---------------------------------------------------------------------------
UPDATE platform_settings
SET setting_value = jsonb_set(COALESCE(setting_value, '{}'::jsonb),
                              '{default_plan_slug}', '"professional"', TRUE)
WHERE setting_key = 'trial'
  AND setting_value->>'default_plan_slug' IS NULL;

INSERT INTO platform_settings (setting_key, setting_value)
SELECT 'trial',
       '{"default_trial_days": 30, "default_plan_slug": "professional"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM platform_settings WHERE setting_key = 'trial');

-- ---------------------------------------------------------------------------
-- 12. Legacy display column: plans are DATA now, so companies.plan must hold
--     ANY super-admin-created slug — the old enum (free/starter/...)
--     cannot. Convert to VARCHAR; the subscription table is the real
--     source of truth, this column stays a denormalized display sync.
--     v_company_summary (migration 9) reads the column, so it is dropped
--     and recreated verbatim around the ALTER.
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS v_company_summary;
ALTER TABLE companies ALTER COLUMN plan DROP DEFAULT;
ALTER TABLE companies ALTER COLUMN plan TYPE VARCHAR(50) USING plan::text;
ALTER TABLE companies ALTER COLUMN plan SET DEFAULT 'free';
CREATE VIEW v_company_summary AS
SELECT c.id,
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
    count(DISTINCT a.id) AS total_accounts,
    count(DISTINCT
        CASE
            WHEN a.status::text = 'active'::text THEN a.id
            ELSE NULL::uuid
        END) AS active_accounts,
    count(DISTINCT cu.id) AS total_users
   FROM companies c
     LEFT JOIN accounts a ON a.company_id = c.id AND a.deleted_at IS NULL
     LEFT JOIN company_users cu ON cu.company_id = c.id AND cu.deleted_at IS NULL AND cu.is_active = true
  WHERE c.deleted_at IS NULL
  GROUP BY c.id;
