-- Pharmacy-scoped settings document.
--
-- A single JSONB column on pharmacies keeps per-pharmacy preferences
-- (receipt/print configuration today, more namespaces later) close to the
-- entity they belong to. The API layer owns validation and defaults, so the
-- column itself stays schema-free: unknown keys are preserved on update and
-- a missing key falls back to code defaults on read.
ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}'::jsonb;
