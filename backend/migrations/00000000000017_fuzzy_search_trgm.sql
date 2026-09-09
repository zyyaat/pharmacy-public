-- ============================================
-- Migration 17: Fuzzy search infrastructure (pg_trgm)
-- Purpose: typo-tolerant product search for POS (كاربيمازول ~ كاربيمازون ~ كانبيبالول)
--          and barcode-misread tolerance for scanners.
-- Safety:  CREATE EXTENSION IF NOT EXISTS + CREATE INDEX IF NOT EXISTS — idempotent.
--          GIN trgm indexes accelerate ILIKE '%q%' and the % similarity operator,
--          so every branch of the POS search cascade stays index-backed as the
--          shared catalog grows (global_products is cross-tenant by design).
-- ============================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Name: prefix, substring and fuzzy (typo) matching for Arabic drug names.
CREATE INDEX IF NOT EXISTS idx_global_products_name_trgm
    ON global_products USING gin (name gin_trgm_ops);

-- Generic name: pharmacists often type the molecule (e.g. كاربيمازول).
CREATE INDEX IF NOT EXISTS idx_global_products_generic_name_trgm
    ON global_products USING gin (generic_name gin_trgm_ops);

-- Barcode: scanners misread (transposed/missing digits); trigram similarity
-- catches 1-2 character errors and LIKE-prefix catches truncated scans.
CREATE INDEX IF NOT EXISTS idx_global_products_barcode_trgm
    ON global_products USING gin (barcode gin_trgm_ops);

-- Analyze so the planner picks the new GIN paths immediately after deploy.
ANALYZE global_products;
