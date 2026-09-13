-- Migration: Billing hardening (Task 90 — subscriptions best-practice pass)
--
-- Global best-practice alignment (Stripe Billing model + 2026 SaaS norms):
--   * Idempotency keys on billing mutations: a double-submitted manual
--     payment (double click, retried request) must never double-extend a
--     subscription. payments.idempotency_key carries the client-generated
--     key; a partial unique index makes replays impossible server-side
--     while leaving every other row (webhook-driven payments) untouched.
--   * Refunds are a first-class ledger event: payment_transactions.txn_type
--     already accepts 'refund'; nothing schema-side is needed for the
--     refund action beyond this comment — kept here so the migration that
--     introduces the refund feature is discoverable in one place.
--
-- All statements guarded — replaying is a no-op (house migration style).

ALTER TABLE payments ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(80);

-- Client-generated, admin-scoped: one key == one manual payment, ever.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_idempotency_key
    ON payments(idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payments_status_created
    ON payments(status, created_at DESC);

COMMENT ON COLUMN payments.idempotency_key IS
    'Client-generated key (manual payments): replaying the same key returns the original payment instead of creating a duplicate — Stripe-style idempotency for billing mutations.';
