-- ===========================================================================
-- Migration 16: keep out-of-stock batches visible in current_inventory
-- ===========================================================================
-- PROBLEM (live-reported): when the last unit of a batch was sold, the POS
-- sale set inventory_batches.quantity = 0 and calculate_batch_current_stock
-- summed to 0 as well. The old view filter
--
--     WHERE ib.quantity > 0 OR calculate_batch_current_stock(ib.id) > 0
--
-- therefore dropped the row entirely, and the product vanished from the
-- inventory screen exactly when the pharmacist most needs to see it
-- (reorder time). POS lookup was unaffected (LEFT JOIN + COALESCE), but the
-- inventory page reads this view directly.
--
-- FIX:
--   * Recreate current_inventory WITHOUT the > 0 row filter. Every batch
--     stays visible regardless of quantity; an empty batch now shows as
--     'out_of_stock' instead of disappearing.
--   * Add an explicit 'out_of_stock' status branch (checked first, because
--     quantity 0 is the dominant operational fact), keeping 'low_stock',
--     'expiring_soon', 'quarantined' and 'normal' exactly as before.
--   * Column list and BIGINT money flow-through are IDENTICAL to the
--     migration-14 definition; only the WHERE clause and the status CASE
--     change. No table data is touched.
--
-- Consumers:
--   * GET /pharmacy/inventory        -> now returns sold-out batches (fix).
--   * Dashboard low-stock counters   -> out-of-stock counts toward
--     "quantity <= min_stock_level", which is correct reorder semantics.
--   * POS catalog/lookup (LEFT JOIN) -> SUM over the extra zero rows adds
--     nothing; results unchanged.
-- ===========================================================================

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
        WHEN calculate_batch_current_stock(ib.id) <= 0 THEN 'out_of_stock'
        WHEN calculate_batch_current_stock(ib.id) <= pp.min_stock_level THEN 'low_stock'
        WHEN ib.expiry_date IS NOT NULL
            AND ib.expiry_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'expiring_soon'
        WHEN ib.is_quarantined THEN 'quarantined'
        ELSE 'normal'
    END AS status
FROM inventory_batches ib
JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
JOIN global_products gp ON pp.global_product_id = gp.id
LEFT JOIN branches b ON ib.branch_id = b.id;

COMMENT ON VIEW current_inventory IS
'Pre-calculated view of current inventory - use for dashboards and reports. '
'Every batch row is always present (including quantity = 0) so sold-out '
'products stay visible for reordering; the status column carries '
'out_of_stock for them.';

COMMENT ON COLUMN current_inventory.quantity IS
'Live stock from stock_movements (source of truth); zero means sold out, '
'never hidden.';
