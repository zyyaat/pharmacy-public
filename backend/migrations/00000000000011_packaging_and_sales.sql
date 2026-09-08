-- Pharmacy product packaging rules and the first POS sale ledger.
-- Packaging belongs to the pharmacy product because the same medicine can
-- have different pack sizes or selling rules in different pharmacies.

ALTER TABLE pharmacy_products
    ADD COLUMN IF NOT EXISTS packaging_type VARCHAR(20) NOT NULL DEFAULT 'WHOLE_ONLY',
    ADD COLUMN IF NOT EXISTS units_per_box INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS partial_selling_price NUMERIC(12,4);

ALTER TABLE pharmacy_products
    DROP CONSTRAINT IF EXISTS pharmacy_products_packaging_type_check;

ALTER TABLE pharmacy_products
    ADD CONSTRAINT pharmacy_products_packaging_type_check
    CHECK (packaging_type IN ('WHOLE_ONLY', 'BOX_STRIP'));

ALTER TABLE pharmacy_products
    DROP CONSTRAINT IF EXISTS pharmacy_products_units_per_box_check;

ALTER TABLE pharmacy_products
    ADD CONSTRAINT pharmacy_products_units_per_box_check
    CHECK (units_per_box >= 1);

ALTER TABLE pharmacy_products
    DROP CONSTRAINT IF EXISTS pharmacy_products_partial_price_check;

ALTER TABLE pharmacy_products
    ADD CONSTRAINT pharmacy_products_partial_price_check
    CHECK (partial_selling_price IS NULL OR partial_selling_price >= 0);

CREATE INDEX IF NOT EXISTS idx_pharmacy_products_packaging
    ON pharmacy_products(pharmacy_id, packaging_type);

CREATE TABLE IF NOT EXISTS sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
    total_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sale_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    pharmacy_product_id UUID NOT NULL REFERENCES pharmacy_products(id) ON DELETE RESTRICT,
    batch_id UUID NOT NULL REFERENCES inventory_batches(id) ON DELETE RESTRICT,
    sale_unit VARCHAR(10) NOT NULL CHECK (sale_unit IN ('box', 'strip')),
    quantity NUMERIC(12,4) NOT NULL CHECK (quantity > 0),
    base_quantity NUMERIC(12,4) NOT NULL CHECK (base_quantity > 0),
    unit_price NUMERIC(12,4) NOT NULL CHECK (unit_price >= 0),
    unit_cost NUMERIC(12,4) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sales_pharmacy_created
    ON sales(pharmacy_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale
    ON sale_items(sale_id);

ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pharmacies_can_view_own_sales" ON sales
    FOR SELECT USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

CREATE POLICY "pharmacies_can_insert_own_sales" ON sales
    FOR INSERT WITH CHECK (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

CREATE POLICY "pharmacies_can_view_own_sale_items" ON sale_items
    FOR SELECT USING (
        sale_id IN (
            SELECT id FROM sales
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

CREATE POLICY "pharmacies_can_insert_own_sale_items" ON sale_items
    FOR INSERT WITH CHECK (
        sale_id IN (
            SELECT id FROM sales
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

DROP VIEW IF EXISTS current_inventory;

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
    pp.partial_selling_price,
    pp.packaging_type,
    pp.units_per_box,
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