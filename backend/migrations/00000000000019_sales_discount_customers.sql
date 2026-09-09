-- Invoice discounts + customer accounts (deferred sales) + customer payments.
--
-- Discount design: the checkout resolves the discount to whole piastres and
-- the amount is stored twice — once on the invoice row (sales.discount_amount,
-- for display), and once DISTRIBUTED across the sale_items amounts with the
-- largest-remainder method, so the line amounts always sum exactly to the
-- invoice total. That keeps the returns flow untouched: a refunded line can
-- never exceed what was actually charged for it.
--
-- A sale is either 'cash' (default) or 'credit' (آجل) for a named customer of
-- the same pharmacy. Customer balance = Σ(credit sales − their returns)
-- − Σ(payments). customers/customer_payments follow the same RLS pattern
-- as sales.

CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (length(btrim(name)) > 0),
    phone TEXT NOT NULL DEFAULT '',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customers_pharmacy
    ON customers(pharmacy_id, created_at DESC);

CREATE TABLE IF NOT EXISTS customer_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    amount BIGINT NOT NULL CHECK (amount > 0),
    note TEXT NOT NULL DEFAULT '',
    employee_id UUID NULL,
    company_user_id UUID NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_payments_customer
    ON customer_payments(customer_id, created_at DESC);

ALTER TABLE sales
    ADD COLUMN IF NOT EXISTS discount_amount BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS payment_type VARCHAR(10) NOT NULL DEFAULT 'cash',
    ADD COLUMN IF NOT EXISTS customer_id UUID NULL REFERENCES customers(id) ON DELETE SET NULL;

ALTER TABLE sales DROP CONSTRAINT IF EXISTS sales_discount_amount_check;
ALTER TABLE sales ADD CONSTRAINT sales_discount_amount_check CHECK (discount_amount >= 0);

ALTER TABLE sales DROP CONSTRAINT IF EXISTS sales_payment_type_check;
ALTER TABLE sales ADD CONSTRAINT sales_payment_type_check CHECK (payment_type IN ('cash', 'credit'));

CREATE INDEX IF NOT EXISTS idx_sales_customer
    ON sales(customer_id) WHERE customer_id IS NOT NULL;

-- RLS mirroring the sales tables
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pharmacies_can_view_own_customers" ON customers
    FOR SELECT USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

CREATE POLICY "pharmacies_can_insert_own_customers" ON customers
    FOR INSERT WITH CHECK (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

CREATE POLICY "pharmacies_can_update_own_customers" ON customers
    FOR UPDATE USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

CREATE POLICY "pharmacies_can_view_own_customer_payments" ON customer_payments
    FOR SELECT USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

CREATE POLICY "pharmacies_can_insert_own_customer_payments" ON customer_payments
    FOR INSERT WITH CHECK (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );
