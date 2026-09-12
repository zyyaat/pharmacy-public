-- Migration: Delta Sync foundation (offline-first smart synchronization)
--
-- The mobile offline cache (Task 82/84) was a response-level cache: every
-- prefetch re-downloaded whole lists and overwrote the same cache keys, so
-- opening the app on the internet re-transferred data the device already
-- had, and deletions on the server never propagated to the device.
--
-- This migration gives the delta-sync endpoint (GET /pharmacy/sync?since=)
-- the columns it needs to detect «what changed since the cursor» cheaply:
--
--   sales.updated_at     returns never mutate the invoice but DO update
--                        sales.status (sales_history_handler UPDATE sales);
--                        without updated_at a new credit note on an old
--                        invoice was invisible to any timestamp cursor.
--   customers.updated_at name/phone edits (PUT /customers/:id) had no
--                        timestamp at all; balance drift is detected via
--                        the sales/payments subqueries in the endpoint.
--   sync_tombstones      the generic deletion contract: rows leave the
--                        synced lists only through this table (written in
--                        the same transaction as any future delete), so
--                        the device removes exactly what disappeared.
--
-- All statements are guarded (IF NOT EXISTS / DROP IF EXISTS) so replaying
-- the migration is a no-op, matching the house migration style.

-- ---------------------------------------------------------------------------
-- 1. sales.updated_at + trigger
-- ---------------------------------------------------------------------------
ALTER TABLE sales
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DROP TRIGGER IF EXISTS update_sales_updated_at ON sales;
CREATE TRIGGER update_sales_updated_at BEFORE UPDATE ON sales
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON COLUMN sales.updated_at IS
    'Maintained by trigger; bumped by the returns flow status update so a delta-sync cursor can detect credit notes on old invoices.';

CREATE INDEX IF NOT EXISTS idx_sales_pharmacy_updated
    ON sales(pharmacy_id, updated_at DESC);

-- ---------------------------------------------------------------------------
-- 2. customers.updated_at + trigger
-- ---------------------------------------------------------------------------
ALTER TABLE customers
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

DROP TRIGGER IF EXISTS update_customers_updated_at ON customers;
CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON COLUMN customers.updated_at IS
    'Maintained by trigger; customer row edits are otherwise timestamp-less, which made incremental sync impossible.';

CREATE INDEX IF NOT EXISTS idx_customers_pharmacy_updated
    ON customers(pharmacy_id, updated_at DESC);

-- ---------------------------------------------------------------------------
-- 3. sync_tombstones — the deletion contract for delta sync
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_tombstones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    entity VARCHAR(32) NOT NULL CHECK (entity IN (
        'inventory_batch', 'customer', 'sale', 'stock_movement'
    )),
    record_id UUID NOT NULL,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_tombstones_lookup
    ON sync_tombstones(pharmacy_id, entity, deleted_at DESC);

COMMENT ON TABLE sync_tombstones IS
    'Deletion ledger for delta sync: whenever a synced record is removed, a row is written here in the same transaction; GET /pharmacy/sync returns tombstones newer than the caller cursor as deleted_ids so devices retract exactly what disappeared.';

-- ---------------------------------------------------------------------------
-- 4. Movement change-detection helper index
--    (movements are append-only; the endpoint reads them by created_at per
--    pharmacy through the joins it already uses — this index keeps that
--    scan ordered)
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_stock_movements_created_id
    ON stock_movements(created_at DESC, id DESC);
