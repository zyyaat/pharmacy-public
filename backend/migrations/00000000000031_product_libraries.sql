-- Migration: central product libraries («مكتبات المنتجات المركزية»)
--
-- Turns the existing cross-tenant global_products catalog (which until now
-- grew only from pharmacy-side creation/import and had NO management
-- surface) into a governed, versioned, country-targeted product library
-- system:
--
--   * product_libraries  — named libraries («الأدوية المصرية الأساسية»,
--     «مكتبة السوق السعودي»…) targeted by country_code (NULL = visible to
--     every country) with a publish flag and a version counter.
--   * library_products   — the catalog entries inside a library. The
--     OFFICIAL regulated price lives HERE, not on global_products: the
--     same drug can sit in an Egypt library (EGP price) and a Saudi
--     library (SAR price) as ONE central row. Price is a property of the
--     library↔product relationship.
--   * library_changes    — append-only change log (added / price_changed /
--     metadata_changed / removed) tagged with the version the change
--     belongs to. This is what powers the pharmacy diff screen
--     («أنت على v12 — متاح v14: ‎+43 جديداً، ✎120 سعراً»).
--   * pharmacy_library_syncs — per-pharmacy last-synced version pointer so
--     a pharmacy that already imported a library only ever pulls the delta.
--
-- Version semantics (locked here so every writer agrees):
--   * A library starts at version 1, unpublished. While unpublished, ALL
--     edits are logged with the CURRENT version number (drafting v1).
--   * Publish #1: is_published = true, published_at = now, version stays 1.
--   * After publish, edits are logged with version + 1 (drafting the next
--     release). Publish #N moves version forward by one and stamps
--     published_at — it refuses when no draft changes exist (no empty
--     releases).
--   * Pharmacies diff against library_changes WHERE version > last_synced
--     AND version <= library.version (draft rows for the NEXT release are
--     never leaked to pharmacies).

CREATE TABLE IF NOT EXISTS product_libraries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    country_code VARCHAR(100),           -- NULL = عامة: تظهر لكل الدول (same format as pharmacies.country)
    currency currency_code NOT NULL DEFAULT 'EGP',
    is_published BOOLEAN NOT NULL DEFAULT false,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    published_at TIMESTAMPTZ,
    created_by TEXT,                      -- platform actor id (mirrors platform_audit_logs.actor_id)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_libraries_name_country
    ON product_libraries (LOWER(name), COALESCE(country_code, ''));
CREATE INDEX IF NOT EXISTS idx_product_libraries_country
    ON product_libraries (country_code);

CREATE TABLE IF NOT EXISTS library_products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    library_id UUID NOT NULL REFERENCES product_libraries(id) ON DELETE CASCADE,
    global_product_id UUID NOT NULL REFERENCES global_products(id) ON DELETE CASCADE,
    official_price_piastres BIGINT NOT NULL DEFAULT 0 CHECK (official_price_piastres >= 0),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT library_products_unique UNIQUE (library_id, global_product_id)
);

CREATE INDEX IF NOT EXISTS idx_library_products_product
    ON library_products (global_product_id);

CREATE TABLE IF NOT EXISTS library_changes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    library_id UUID NOT NULL REFERENCES product_libraries(id) ON DELETE CASCADE,
    global_product_id UUID NOT NULL REFERENCES global_products(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    change_type VARCHAR(20) NOT NULL CHECK (change_type IN
        ('added', 'price_changed', 'metadata_changed', 'removed')),
    old_price_piastres BIGINT,
    new_price_piastres BIGINT,
    summary TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_library_changes_library_version
    ON library_changes (library_id, version);
CREATE INDEX IF NOT EXISTS idx_library_changes_product
    ON library_changes (global_product_id);

CREATE TABLE IF NOT EXISTS pharmacy_library_syncs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    library_id UUID NOT NULL REFERENCES product_libraries(id) ON DELETE CASCADE,
    last_synced_version INTEGER NOT NULL DEFAULT 0 CHECK (last_synced_version >= 0),
    synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pharmacy_library_syncs_unique UNIQUE (pharmacy_id, library_id)
);

-- Catalog enrichment: provenance + the admin verification badge.
ALTER TABLE global_products ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE global_products ADD COLUMN IF NOT EXISTS source VARCHAR(20) NOT NULL DEFAULT 'pharmacy';

-- CHECK for source is added idempotently (ADD CONSTRAINT has no IF NOT EXISTS).
-- Everything that existed before this migration came from pharmacy-side
-- creation/import, so the default 'pharmacy' backfills provenance correctly;
-- platform-created rows set 'platform_admin' explicitly.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'global_products_source_check'
    ) THEN
        ALTER TABLE global_products ADD CONSTRAINT global_products_source_check
            CHECK (source IN ('platform_admin', 'pharmacy', 'import'));
    END IF;
END $$;
