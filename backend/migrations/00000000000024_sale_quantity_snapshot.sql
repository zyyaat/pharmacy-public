-- Migration: Invoice Quantity Snapshot (barcode system v1 — Task 86)
-- Design: barcode-design-v2-review.md §5.3 (Final Decision 12)
--
-- Freezes the cashier's intent at write time so a later change to a
-- product's units_per_box can NEVER reinterpret yesterday's invoice:
--   sale_quantity          = the quantity as entered in sale_unit
--                            (boxes on box lines, strips on strip lines)
--   units_per_box_snapshot = units_per_box of the product at sale time
--
-- Existing rows stay NULL on purpose: they are interpreted through the
-- documented legacy fallback (base / current units_per_box), exactly like
-- the report's transition clause. No backfill, no reinterpretation of
-- history, no rounding: all money and return math keeps reading
-- base_quantity / piastres untouched.

ALTER TABLE sale_items
    ADD COLUMN IF NOT EXISTS sale_quantity NUMERIC(12,4),
    ADD COLUMN IF NOT EXISTS units_per_box_snapshot INTEGER;

COMMENT ON COLUMN sale_items.sale_quantity IS
    'Cashier intent: quantity as entered in sale_unit. NULL = pre-snapshot row (legacy fallback: base/current units_per_box).';

COMMENT ON COLUMN sale_items.units_per_box_snapshot IS
    'units_per_box at sale time; freezes the historical interpretation of the invoice. NULL = pre-snapshot row.';
