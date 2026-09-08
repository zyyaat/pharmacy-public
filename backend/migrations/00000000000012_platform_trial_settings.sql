-- Platform-wide trial configuration and company-user inventory actors.
--
-- Company admins/managers can operate a pharmacy during its trial without
-- being duplicated as pharmacy employees. Inventory and POS ledgers retain
-- the acting company user for auditability.

CREATE TABLE IF NOT EXISTS platform_settings (
    setting_key VARCHAR(100) PRIMARY KEY,
    setting_value JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_by UUID REFERENCES company_users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO platform_settings (setting_key, setting_value)
VALUES ('trial', jsonb_build_object('default_trial_days', 30))
ON CONFLICT (setting_key) DO NOTHING;

ALTER TABLE stock_movements
    ALTER COLUMN created_by DROP NOT NULL;

ALTER TABLE stock_movements
    ADD COLUMN IF NOT EXISTS created_by_company_user_id UUID
        REFERENCES company_users(id) ON DELETE CASCADE;

ALTER TABLE stock_movements
    DROP CONSTRAINT IF EXISTS stock_movements_actor_required;

ALTER TABLE stock_movements
    ADD CONSTRAINT stock_movements_actor_required
    CHECK (created_by IS NOT NULL OR created_by_company_user_id IS NOT NULL);

CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_movements_company_user_idempotency
    ON stock_movements (created_by_company_user_id, idempotency_key)
    WHERE created_by_company_user_id IS NOT NULL
      AND idempotency_key IS NOT NULL;

ALTER TABLE sales
    ALTER COLUMN employee_id DROP NOT NULL;

ALTER TABLE sales
    ADD COLUMN IF NOT EXISTS company_user_id UUID
        REFERENCES company_users(id) ON DELETE CASCADE;

ALTER TABLE sales
    DROP CONSTRAINT IF EXISTS sales_actor_required;

ALTER TABLE sales
    ADD CONSTRAINT sales_actor_required
    CHECK (employee_id IS NOT NULL OR company_user_id IS NOT NULL);