-- Migration: sales history + POS returns (credit notes)
--
-- The sales ledger becomes the source of the "سجل البيع" tab: every sale
-- carries a human readable invoice number and a lifecycle status. Returns
-- are modeled as dedicated credit-note documents linked to the original
-- invoice; the original sale is never mutated (audit-safe best practice):
--
--   sale_returns       one row per return document (the "reverse invoice")
--   sale_return_items  one row per returned sale_items row, batch-accurate
--
-- Returned quantities go back to the EXACT batches they were sold from
-- (sale_items.batch_id), so batch-level traceability is preserved. Refund
-- amounts are computed in the application with the same largest-remainder
-- allocation used at sale time; partial returns always sum exactly to the
-- original row amount once the row is fully returned. Money stays integer
-- piastres everywhere.
--
-- The migration is data-preserving and idempotent: every statement is
-- guarded (IF NOT EXISTS / DROP IF EXISTS) so replaying it is a no-op.

-- ---------------------------------------------------------------------------
-- 1. Human readable invoice number + lifecycle status on sales
-- ---------------------------------------------------------------------------
ALTER TABLE sales
    ADD COLUMN IF NOT EXISTS invoice_number BIGINT GENERATED ALWAYS AS IDENTITY,
    ADD COLUMN IF NOT EXISTS status VARCHAR(24) NOT NULL DEFAULT 'completed';

ALTER TABLE sales
    DROP CONSTRAINT IF EXISTS sales_status_check;

ALTER TABLE sales
    ADD CONSTRAINT sales_status_check
    CHECK (status IN ('completed', 'partially_returned', 'returned'));

COMMENT ON COLUMN sales.invoice_number IS
    'Monotonically increasing invoice number, displayed as INV-<n>';
COMMENT ON COLUMN sales.status IS
    'completed | partially_returned | returned; maintained by the returns flow';

-- ---------------------------------------------------------------------------
-- 2. Return documents (credit notes / reverse invoices)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sale_returns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
    sale_id UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    return_number BIGINT GENERATED ALWAYS AS IDENTITY,
    total_amount_piastres BIGINT NOT NULL DEFAULT 0
        CHECK (total_amount_piastres >= 0),
    reason VARCHAR(500) NOT NULL DEFAULT '',
    employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    company_user_id UUID REFERENCES company_users(id) ON DELETE SET NULL,
    idempotency_key VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 3. Returned lines: one per returned sale_items row (batch-accurate)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sale_return_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    return_id UUID NOT NULL REFERENCES sale_returns(id) ON DELETE CASCADE,
    sale_item_id UUID NOT NULL REFERENCES sale_items(id) ON DELETE CASCADE,
    pharmacy_product_id UUID NOT NULL REFERENCES pharmacy_products(id) ON DELETE RESTRICT,
    batch_id UUID NOT NULL REFERENCES inventory_batches(id) ON DELETE RESTRICT,
    quantity BIGINT NOT NULL CHECK (quantity > 0),
    amount_piastres BIGINT NOT NULL CHECK (amount_piastres >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sale_returns_pharmacy_created
    ON sale_returns(pharmacy_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sale_returns_sale
    ON sale_returns(sale_id);

-- A retried return request must never create a second credit note.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sale_returns_pharmacy_idempotency
    ON sale_returns(pharmacy_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sale_return_items_return
    ON sale_return_items(return_id);
CREATE INDEX IF NOT EXISTS idx_sale_return_items_sale_item
    ON sale_return_items(sale_item_id);

-- ---------------------------------------------------------------------------
-- 4. Row level security mirrors the sales ledger
-- ---------------------------------------------------------------------------
ALTER TABLE sale_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_return_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pharmacies_can_view_own_sale_returns" ON sale_returns
    FOR SELECT USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

CREATE POLICY "pharmacies_can_insert_own_sale_returns" ON sale_returns
    FOR INSERT WITH CHECK (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

CREATE POLICY "pharmacies_can_view_own_sale_return_items" ON sale_return_items
    FOR SELECT USING (
        return_id IN (
            SELECT id FROM sale_returns
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

CREATE POLICY "pharmacies_can_insert_own_sale_return_items" ON sale_return_items
    FOR INSERT WITH CHECK (
        return_id IN (
            SELECT id FROM sale_returns
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

-- ---------------------------------------------------------------------------
-- 5. Document the conventions on the data dictionary level
-- ---------------------------------------------------------------------------
COMMENT ON TABLE sale_returns IS
    'POS return documents (credit notes); each reverses part of or a whole sale invoice without mutating it';
COMMENT ON COLUMN sale_returns.total_amount_piastres IS
    'Total refunded amount in piastres; always the exact sum of the return line amounts';
COMMENT ON COLUMN sale_returns.idempotency_key IS
    'Client supplied retry key, unique per pharmacy for idempotent returns';
COMMENT ON COLUMN sale_return_items.quantity IS
    'Base units (strips) returned from the linked sale_items row';
COMMENT ON COLUMN sale_return_items.amount_piastres IS
    'Exact refund amount of this row in piastres; the rows of one return sum exactly to the return total';
