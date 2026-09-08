-- Migration: durable idempotency for inventory mutations
--
-- A retry of a stock mutation must not create a second movement. The key is
-- scoped to the employee who submitted the mutation and is intentionally
-- nullable so historical movements remain valid.

ALTER TABLE stock_movements
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128);

CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_movements_created_by_idempotency
    ON stock_movements (created_by, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

COMMENT ON COLUMN stock_movements.idempotency_key IS
    'Client supplied retry key, unique per employee for idempotent inventory writes';