-- Migration: money in integer minor units (piastres)
--
-- Every monetary amount in the system is now an integer count of the
-- currency's smallest unit. For EGP the minor unit is the piastre and
-- currency_minor_unit = 2, so 1 EGP is stored as 100 and a product priced
-- at 100 EGP is stored as 10000.
--
-- Rules enforced from this migration onward:
--   * Money columns are BIGINT. Integer addition, subtraction and
--     multiplication are exact; fractional money can never reappear.
--   * Quantity columns stay NUMERIC (they are exact decimals in PostgreSQL
--     and are always whole values written by the application); the API layer
--     exposes them as integers.
--   * The only permitted divisions live in the application's money package
--     with deterministic rounding (half-up) or largest-remainder allocation
--     whose parts always sum to the original amount.
--
-- The conversion is data-preserving and idempotent:
--   * a column is converted only while it is still fractional (numeric),
--     so replaying this migration is a no-op,
--   * values are scaled by exactly 100 via ROUND on the exact numeric
--     values, which is lossless,
--   * dependent objects (the current_inventory view and the derived
--     inventory_batches.total_cost column) are dropped and recreated with
--     identical definitions.
-- Column names intentionally stay unchanged so dependent views keep their
-- shape. The piastres semantic is carried by the API contract, whose money
-- fields are named *_piastres.

-- ---------------------------------------------------------------------------
-- 1. Currency metadata on pharmacies
-- ---------------------------------------------------------------------------
ALTER TABLE pharmacies
    ADD COLUMN IF NOT EXISTS currency_minor_unit SMALLINT NOT NULL DEFAULT 2;

-- ---------------------------------------------------------------------------
-- 2. Detach the dependent view FIRST: PostgreSQL refuses to alter the type
--    of any column referenced by a view. The view is recreated identically
--    in step 5 after all conversions.
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS current_inventory;

-- ---------------------------------------------------------------------------
-- 3. Convert every fractional money column to BIGINT piastres (x100)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT table_name, column_name FROM (VALUES
            ('pharmacy_products', 'cost_price'),
            ('pharmacy_products', 'selling_price'),
            ('pharmacy_products', 'partial_selling_price'),
            ('sales',             'total_amount'),
            ('sale_items',        'unit_price'),
            ('sale_items',        'unit_cost'),
            ('stock_movements',   'unit_cost'),
            ('stock_movements',   'total_cost')
        ) AS t(table_name, column_name)
    LOOP
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = r.table_name
              AND column_name = r.column_name
              AND data_type IN ('numeric', 'real', 'double precision')
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I ALTER COLUMN %I TYPE BIGINT USING ROUND(%I * 100)::bigint',
                r.table_name, r.column_name, r.column_name
            );
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 4. inventory_batches.cost_per_unit -> BIGINT
--    The derived total_cost column must be rebuilt because PostgreSQL does
--    not allow altering a column referenced by a generated column. The old
--    value on the hosted database is a plain (non-generated) numeric; either
--    way it is recomputed exactly from quantity * cost_per_unit.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'inventory_batches'
          AND column_name = 'total_cost'
    ) THEN
        ALTER TABLE inventory_batches DROP COLUMN total_cost;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'inventory_batches'
          AND column_name = 'cost_per_unit'
          AND data_type IN ('numeric', 'real', 'double precision')
    ) THEN
        ALTER TABLE inventory_batches
            ALTER COLUMN cost_per_unit TYPE BIGINT
            USING ROUND(cost_per_unit * 100)::bigint;
    END IF;
END $$;

ALTER TABLE inventory_batches
    ADD COLUMN IF NOT EXISTS total_cost BIGINT
    GENERATED ALWAYS AS ((quantity * cost_per_unit)::bigint) STORED;

-- ---------------------------------------------------------------------------
-- 5. Recreate current_inventory with the exact migration-11 definition.
--    Money columns flow through as BIGINT automatically.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 6. sale_items row amounts
--    amount_piastres is the authoritative revenue share of this batch row;
--    the rows of one sale line always sum EXACTLY to the line total even
--    when a line was fulfilled from several batches. cost_amount_piastres
--    is the exact cost of the strips taken from this batch.
-- ---------------------------------------------------------------------------
ALTER TABLE sale_items
    ADD COLUMN IF NOT EXISTS amount_piastres BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS cost_amount_piastres BIGINT NOT NULL DEFAULT 0;

-- Best-effort backfill for historical rows written before this migration
-- (legacy rows store the sale-unit quantity, so unit_price * quantity is the
-- closest exact representation). Rows already carrying an amount are kept.
UPDATE sale_items
SET amount_piastres = ROUND(unit_price * quantity)::bigint,
    cost_amount_piastres = ROUND(base_quantity)::bigint * unit_cost
WHERE amount_piastres = 0
  AND cost_amount_piastres = 0
  AND (unit_price <> 0 OR unit_cost <> 0);

-- ---------------------------------------------------------------------------
-- 7. Sale idempotency: a retried checkout must never create a second sale
-- ---------------------------------------------------------------------------
ALTER TABLE sales
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_pharmacy_idempotency
    ON sales (pharmacy_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 8. Document the convention on the data dictionary level
-- ---------------------------------------------------------------------------
COMMENT ON COLUMN pharmacy_products.selling_price IS
    'Selling price per whole box in piastres (1 EGP = 100 piastres); integer money';
COMMENT ON COLUMN pharmacy_products.partial_selling_price IS
    'Explicit selling price per strip in piastres; the application requires it for BOX_STRIP products';
COMMENT ON COLUMN pharmacy_products.cost_price IS
    'Purchase cost per whole box in piastres; integer money';
COMMENT ON COLUMN sales.total_amount IS
    'Invoice total in piastres; always the exact sum of the line totals';
COMMENT ON COLUMN sale_items.unit_price IS
    'Reference unit price of the sale line in piastres (per box or per strip as sold)';
COMMENT ON COLUMN sale_items.amount_piastres IS
    'Authoritative revenue share of this batch row in piastres; batch rows of one line sum exactly to the line total';
COMMENT ON COLUMN inventory_batches.cost_per_unit IS
    'Cost per base unit (strip) in piastres; integer money';
COMMENT ON COLUMN sales.idempotency_key IS
    'Client supplied retry key, unique per pharmacy for idempotent POS checkouts';
