-- Migration: Internal Barcode Generation (barcode system v1 — Task 86)
-- Design: barcode-design-v2-review.md (§1, §2, §7.1, §7.2)
--
-- What this does:
--  1. Platform-wide atomic sequence feeding RCN EAN-13 generation
--     (20 + 10-digit platform sequence + Mod-10 check digit).
--  2. Backfills barcode_type with the new LOCKED vocabulary derived
--     mechanically from the stored code (no user choice involved):
--       GTIN_EAN13 | GTIN_UPCA | RCN_EAN13 | CODE128 | OTHER
--  3. Locks the vocabulary with a CHECK constraint and drops the
--     misleading 'EAN13' default so an absent barcode no longer
--     pretends to be a typed one.
--  4. Documents the dormant inventory_batches.barcode column.
--
-- The manual-entry guard stays exactly as before: the unique partial
-- index idx_global_products_unique_barcode (migration 2).

-- ============================================
-- 1) Atomic platform sequence for internal barcodes
--    nextval() is atomic and never re-issues a value, so generated
--    codes cannot collide with each other even under parallel
--    generation. The cap mirrors the 10-digit payload: exhaustion
--    fails loudly instead of emitting a structurally wrong barcode.
-- ============================================
CREATE SEQUENCE IF NOT EXISTS product_internal_barcode_seq
    AS BIGINT START WITH 1 INCREMENT BY 1 MAXVALUE 9999999999;

COMMENT ON SEQUENCE product_internal_barcode_seq IS
    'Platform-wide source for internal RCN EAN-13 payloads (20 + 10-digit sequence + Mod-10).';

-- ============================================
-- 2) Check-digit validators (migration-local helpers, dropped below)
-- ============================================
CREATE OR REPLACE FUNCTION _ean13_is_valid(p_code TEXT) RETURNS BOOLEAN AS $$
DECLARE
    i INT;
    d INT;
    s INT := 0;
BEGIN
    IF p_code IS NULL OR length(p_code) <> 13 OR p_code !~ '^[0-9]+$' THEN
        RETURN FALSE;
    END IF;
    FOR i IN 1..12 LOOP
        d := SUBSTRING(p_code FROM i FOR 1)::INT;
        IF i % 2 = 1 THEN s := s + d; ELSE s := s + 3 * d; END IF;
    END LOOP;
    RETURN ((10 - (s % 10)) % 10) = SUBSTRING(p_code FROM 13 FOR 1)::INT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION _upca_is_valid(p_code TEXT) RETURNS BOOLEAN AS $$
DECLARE
    i INT;
    d INT;
    s INT := 0;
BEGIN
    IF p_code IS NULL OR length(p_code) <> 12 OR p_code !~ '^[0-9]+$' THEN
        RETURN FALSE;
    END IF;
    FOR i IN 1..11 LOOP
        d := SUBSTRING(p_code FROM i FOR 1)::INT;
        IF i % 2 = 1 THEN s := s + 3 * d; ELSE s := s + d; END IF;
    END LOOP;
    RETURN ((10 - (s % 10)) % 10) = SUBSTRING(p_code FROM 12 FOR 1)::INT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================
-- 3) Backfill: derive the locked type from the stored code.
--    Legacy rows carry the useless default 'EAN13'; rows without a
--    barcode lose the type entirely (NULL = untyped, like the code).
-- ============================================
UPDATE global_products
SET barcode_type = CASE
    WHEN barcode IS NULL THEN NULL
    WHEN length(barcode) = 13 AND _ean13_is_valid(barcode)
         AND SUBSTRING(barcode FROM 1 FOR 1) = '2' THEN 'RCN_EAN13'
    WHEN length(barcode) = 13 AND _ean13_is_valid(barcode) THEN 'GTIN_EAN13'
    WHEN length(barcode) = 12 AND _upca_is_valid(barcode) THEN 'GTIN_UPCA'
    WHEN barcode ~ '[^0-9]' THEN 'CODE128'
    ELSE 'OTHER'
END
WHERE barcode IS NOT NULL OR barcode_type IS NOT NULL;

-- ============================================
-- 4) Lock the vocabulary. NULL remains legal (product without a
--    barcode — the import path has always allowed it).
-- ============================================
ALTER TABLE global_products ALTER COLUMN barcode_type DROP DEFAULT;

ALTER TABLE global_products
    DROP CONSTRAINT IF EXISTS global_products_barcode_type_check;

ALTER TABLE global_products
    ADD CONSTRAINT global_products_barcode_type_check
    CHECK (barcode_type IS NULL OR barcode_type IN
        ('GTIN_EAN13', 'GTIN_UPCA', 'RCN_EAN13', 'CODE128', 'OTHER'));

COMMENT ON COLUMN global_products.barcode_type IS
    'Locked vocabulary derived server-side at write time: GTIN_EAN13 | GTIN_UPCA | RCN_EAN13 | CODE128 | OTHER. NULL = no barcode.';

COMMENT ON COLUMN global_products.barcode IS
    'Primary barcode. Manufacturer codes are GTINs; internal codes are RCN EAN-13 (prefix 20, GS1 GS §8.2) generated server-side and unique through idx_global_products_unique_barcode. Never publish internal codes outside this system.';

COMMENT ON COLUMN inventory_batches.barcode IS
    'Dormant in v1: batch-level barcodes have no scan path yet (POS resolves global_products.barcode only; the batch is chosen server-side by FEFO). Reserved for future warehouse flows — do not merge with the product barcode.';

-- ============================================
-- 5) Clean up the migration-local helpers
-- ============================================
DROP FUNCTION _ean13_is_valid(TEXT);
DROP FUNCTION _upca_is_valid(TEXT);
