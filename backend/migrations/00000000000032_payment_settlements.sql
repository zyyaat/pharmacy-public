-- Migration: Payment Settlement & Subscription Reconciliation (Phase S1)
--
-- Separates the three money questions the billing ledger previously answered
-- with one flag ("succeeded"):
--
--   1. CONFIRMED  — did the provider capture the money? (webhook verified
--                   paymentStatus=paid, a pull resync, or a manual entry)
--   2. ACTIVATED  — did the subscription extend? (applySucceededPaymentTx —
--                   unchanged, still the single transition)
--   3. SETTLED    — did the money reach OUR bank? XPay pays out in batches
--                   from a schedule the XPay ops team controls; there is NO
--                   payout API and NO payout webhook (docs.xpay.app →
--                   Payouts and settlement). So settlement-to-bank is
--                   recorded as an OPERATOR-VERIFIED fact: the super admin
--                   matches the payout batch in the XPay dashboard and
--                   records it here with reference + note + audit trail.
--
-- What is automatic after this migration: confirmation timestamps/sources,
-- provider refunds landing through charge.refunded (passive recording — we
-- never initiate an XPay refund from the API), a pull resync against
-- GET /checkout/sessions/:id that closes the lost-webhook gap, a review
-- queue for amount/currency conflicts, and human-readable references
-- (SUB-/PAY-) for subscriptions and payments.
--
-- All statements guarded — replaying the migration is a no-op (house style).

-- ---------------------------------------------------------------------------
-- 1. Human-readable billing references (SUB-00001 / PAY-00001)
--    Nullable columns + BEFORE INSERT triggers: every INSERT site keeps
--    working untouched, and the trigger assigns the reference when absent.
--    Sequences are positioned past the backfilled maxima, so future numbers
--    never collide.
-- ---------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS subscription_reference_seq;
CREATE SEQUENCE IF NOT EXISTS payment_number_seq;

ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS reference VARCHAR(30);
ALTER TABLE payments     ADD COLUMN IF NOT EXISTS number     VARCHAR(30);

-- Backfill: number the existing rows oldest-first (re-run safe — only NULLs).
WITH ranked AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM subscriptions WHERE reference IS NULL
)
UPDATE subscriptions s
SET reference = 'SUB-' || lpad(ranked.rn::text, 5, '0')
FROM ranked WHERE ranked.id = s.id;

WITH ranked AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM payments WHERE number IS NULL
)
UPDATE payments p
SET number = 'PAY-' || lpad(ranked.rn::text, 5, '0')
FROM ranked WHERE ranked.id = p.id;

-- Position the sequences past every number already in use (digits suffix).
SELECT setval('subscription_reference_seq',
    GREATEST((SELECT COALESCE(MAX((regexp_replace(reference, '\D', '', 'g'))::bigint), 0)
              FROM subscriptions WHERE reference IS NOT NULL), 1));
SELECT setval('payment_number_seq',
    GREATEST((SELECT COALESCE(MAX((regexp_replace(number, '\D', '', 'g'))::bigint), 0)
              FROM payments WHERE number IS NOT NULL), 1));

CREATE UNIQUE INDEX IF NOT EXISTS uq_subscriptions_reference
    ON subscriptions(reference) WHERE reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_number
    ON payments(number) WHERE number IS NOT NULL;

CREATE OR REPLACE FUNCTION assign_subscription_reference() RETURNS trigger AS $$
BEGIN
    IF NEW.reference IS NULL OR NEW.reference = '' THEN
        NEW.reference := 'SUB-' || lpad(nextval('subscription_reference_seq')::text, 5, '0');
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_subscriptions_reference ON subscriptions;
CREATE TRIGGER trg_subscriptions_reference BEFORE INSERT ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION assign_subscription_reference();

CREATE OR REPLACE FUNCTION assign_payment_number() RETURNS trigger AS $$
BEGIN
    IF NEW.number IS NULL OR NEW.number = '' THEN
        NEW.number := 'PAY-' || lpad(nextval('payment_number_seq')::text, 5, '0');
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_payments_number ON payments;
CREATE TRIGGER trg_payments_number BEFORE INSERT ON payments
    FOR EACH ROW EXECUTE FUNCTION assign_payment_number();

-- ---------------------------------------------------------------------------
-- 2. payments confirmation + failure + review + refund tracking
-- ---------------------------------------------------------------------------
ALTER TABLE payments ADD COLUMN IF NOT EXISTS confirmed_at          TIMESTAMPTZ;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS confirmation_source   VARCHAR(20);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS failure_code          VARCHAR(100);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS failure_message       TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS refunded_amount_piastres BIGINT NOT NULL DEFAULT 0;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS needs_review          BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS review_reason         TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'payments_confirmation_source_check'
          AND conrelid = 'payments'::regclass
    ) THEN
        ALTER TABLE payments ADD CONSTRAINT payments_confirmation_source_check
            CHECK (confirmation_source IS NULL
                   OR confirmation_source IN ('webhook','sync','manual'));
    END IF;
END $$;

-- Backfill: every succeeded payment was confirmed by its proving path —
-- webhooks (online) or the operator's own entry (manual).
UPDATE payments SET confirmed_at = COALESCE(confirmed_at, updated_at, NOW()),
                     confirmation_source = CASE
                         WHEN provider = 'manual' THEN 'manual'
                         ELSE 'webhook' END
WHERE status = 'succeeded' AND confirmed_at IS NULL;

-- Refund backfill: status already says refunded; the amount column now says
-- how much (historical refunds were full-refund semantics).
UPDATE payments SET refunded_amount_piastres = amount_piastres
WHERE status = 'refunded' AND refunded_amount_piastres = 0;

CREATE INDEX IF NOT EXISTS idx_payments_needs_review
    ON payments(needs_review, created_at DESC) WHERE needs_review;
CREATE INDEX IF NOT EXISTS idx_payments_provider_status
    ON payments(provider, status, created_at DESC);

-- ---------------------------------------------------------------------------
-- 3. payment_transactions — the append-only event ledger grows four event
--    kinds: sync (pull resync), settlement (operator settlement actions),
--    review (manual review flags), status_change (guarded manual flips).
--    Drop+re-add keeps replays idempotent even when the ledger already ran
--    an earlier CHECK shape.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    ALTER TABLE payment_transactions DROP CONSTRAINT IF EXISTS payment_transactions_txn_type_check;
    ALTER TABLE payment_transactions ADD CONSTRAINT payment_transactions_txn_type_check
        CHECK (txn_type IN ('intent','webhook','refund','void',
                            'sync','settlement','review','status_change'));
END $$;

-- ---------------------------------------------------------------------------
-- 4. payment_settlements — the operator-verified financial state of one
--    online payment with the provider. One row per payment (UNIQUE), state
--    evolves in place; every transition also writes a 'settlement' event to
--    payment_transactions (the history), so this table stays a clean
--    current-state snapshot for queries and the reconciliation report.
--    Manual payments (provider='manual') have NO settlement row by design:
--    there is no provider to settle with.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payment_settlements (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id                  UUID NOT NULL UNIQUE REFERENCES payments(id) ON DELETE CASCADE,
    provider                    VARCHAR(30) NOT NULL,
    status                      VARCHAR(20) NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','settled','partially_settled',
                                                  'failed','disputed','unknown')),
    settled_amount_piastres     BIGINT,
    fees_piastres               BIGINT,
    currency                    CHAR(3) NOT NULL DEFAULT 'EGP',
    provider_settlement_reference VARCHAR(100),
    settled_at                  TIMESTAMPTZ,
    last_synced_at              TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_settlements_status
    ON payment_settlements(status, updated_at DESC);

DROP TRIGGER IF EXISTS update_payment_settlements_updated_at ON payment_settlements;
CREATE TRIGGER update_payment_settlements_updated_at BEFORE UPDATE ON payment_settlements
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE payment_settlements IS
    'Operator-verified settlement state per ONLINE payment. pending = provider captured (webhook/sync confirmed) but the bank payout is not yet matched; settled/partially_settled = the operator matched an XPay payout batch (reference + note + audit required); unknown/disputed = data conflict or chargeback — always needs_review. XPay exposes payouts in the dashboard only (no payout API/webhook), so settlement-to-bank is recorded here as an operator-verified fact, never guessed.';

-- Backfill: historical ONLINE successes were captured by their provider but
-- their bank payout was never verified — they start as honest 'pending'.
INSERT INTO payment_settlements
    (payment_id, provider, status, currency, settled_amount_piastres, last_synced_at)
SELECT p.id, p.provider, 'pending', p.currency, p.amount_piastres, NOW()
FROM payments p
WHERE p.status = 'succeeded'
  AND p.provider <> 'manual'
  AND NOT EXISTS (SELECT 1 FROM payment_settlements ps WHERE ps.payment_id = p.id)
ON CONFLICT (payment_id) DO NOTHING;
