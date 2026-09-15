-- Migration: Support system — live chat + tickets (Phase T1)
--
-- Two products that share one spine:
--
--   CONVERSATION — the live chat channel between ONE company and the
--                  platform support team. Append-only messages, per-side
--                  unread counters, per-side close. Never plan-gated: a
--                  locked-out company must still be able to reach support.
--   TICKET       — the work item a support conversation may escalate into
--                  (or start as): TKT-00001, status/priority/category,
--                  resolution note. Status changes surface as system
--                  messages inside the linked conversation so both sides
--                  see the same history in one place.
--   ATTACHMENT   — small files (screenshots/PDF, <= 2 MiB) stored inline in
--                  the database. There is no object storage in this stack;
--                  support traffic volume is tiny and every read is
--                  company-scoped, so a bytea column is the honest choice
--                  until real storage exists.
--
-- Real-time delivery is a WebSocket hub in the app process; the DATABASE
-- stays the source of truth (REST is authoritative, WS is an accelerator —
-- a dropped socket must never lose a message). See internal/handlers/
-- support_hub.go.
--
-- All statements guarded — replaying the migration is a no-op (house style).

-- ---------------------------------------------------------------------------
-- 1. Conversations (the chat channel)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS support_conversations (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id                  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subject                     VARCHAR(200) NOT NULL DEFAULT '',
    status                      VARCHAR(20) NOT NULL DEFAULT 'open'
                                CHECK (status IN ('open', 'closed')),
    closed_by                   VARCHAR(10) CHECK (closed_by IN ('platform', 'pharmacy')),
    last_message_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_preview        TEXT NOT NULL DEFAULT '',
    -- Which side wrote the last HUMAN message (system rows never touch this) —
    -- powers the platform's «unanswered» inbox filter distinctly from unread.
    last_sender_realm           VARCHAR(10) CHECK (last_sender_realm IN ('platform', 'pharmacy')),
    -- Unread bookkeeping: append-only messages let counters stay exact with
    -- plain increments/decrements (no per-message read rows needed).
    platform_unread_count       INTEGER NOT NULL DEFAULT 0,
    company_unread_count        INTEGER NOT NULL DEFAULT 0,
    platform_last_read_message_id UUID,
    company_last_read_message_id  UUID,
    -- Email notification throttling (Brevo): one mail per quiet window per
    -- side, sent only when the receiving side has no live WS connection.
    last_notified_platform_at   TIMESTAMPTZ,
    last_notified_company_at    TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_conversations_company
    ON support_conversations (company_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_conversations_platform_inbox
    ON support_conversations (status, platform_unread_count DESC, last_message_at DESC);

DROP TRIGGER IF EXISTS trg_support_conversations_updated_at ON support_conversations;
CREATE TRIGGER trg_support_conversations_updated_at BEFORE UPDATE ON support_conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE support_conversations IS
'Live support chat channel between one company and the platform team. Unread counters are maintained transactionally by the message writers; closed conversations reject new messages from both sides.';

-- ---------------------------------------------------------------------------
-- 2. Attachments (created first — messages reference them)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS support_attachments (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id        UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    uploaded_by_realm VARCHAR(10) NOT NULL CHECK (uploaded_by_realm IN ('platform', 'pharmacy')),
    uploaded_by       UUID,
    file_name         VARCHAR(255) NOT NULL,
    mime_type         VARCHAR(100) NOT NULL,
    size_bytes        BIGINT NOT NULL CHECK (size_bytes <= 2097152),
    content           BYTEA NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE support_attachments IS
'Support chat attachments (png/jpeg/webp/pdf, <= 2 MiB) stored inline; the handler enforces the mime allow-list and every read is scoped to the owning company.';

-- ---------------------------------------------------------------------------
-- 3. Messages (append-only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS support_messages (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id  UUID NOT NULL REFERENCES support_conversations(id) ON DELETE CASCADE,
    sender_realm     VARCHAR(10) NOT NULL CHECK (sender_realm IN ('platform', 'pharmacy')),
    sender_id        UUID,
    sender_name      VARCHAR(150) NOT NULL DEFAULT '',
    body             TEXT NOT NULL CHECK (char_length(body) <= 4000),
    attachment_id    UUID REFERENCES support_attachments(id) ON DELETE SET NULL,
    is_system        BOOLEAN NOT NULL DEFAULT FALSE,
    system_kind      VARCHAR(40),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_messages_conversation
    ON support_messages (conversation_id, created_at DESC, id DESC);

COMMENT ON TABLE support_messages IS
'Append-only support chat messages. System rows (is_system) record ticket lifecycle and conversation state changes inside the chat itself — one history for both sides.';

-- ---------------------------------------------------------------------------
-- 4. Tickets (the work item — TKT-00001 like SUB-/PAY- before it)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS support_tickets (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id       UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    conversation_id  UUID REFERENCES support_conversations(id) ON DELETE SET NULL,
    number           VARCHAR(30),
    subject          VARCHAR(200) NOT NULL,
    status           VARCHAR(20) NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open', 'in_progress', 'waiting_customer', 'resolved', 'closed')),
    priority         VARCHAR(10) NOT NULL DEFAULT 'normal'
                     CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    category         VARCHAR(40) NOT NULL DEFAULT 'other'
                     CHECK (category IN ('billing', 'technical', 'inventory', 'account', 'feature_request', 'other')),
    assigned_to      UUID,
    resolution_note  TEXT,
    resolved_at      TIMESTAMPTZ,
    closed_at        TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE SEQUENCE IF NOT EXISTS support_ticket_number_seq;

-- Backfill: number the existing rows oldest-first (re-run safe — only NULLs).
WITH ranked AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM support_tickets WHERE number IS NULL
)
UPDATE support_tickets t
SET number = 'TKT-' || lpad(ranked.rn::text, 5, '0')
FROM ranked WHERE ranked.id = t.id;

-- Position the sequence past every number already in use (digits suffix).
-- is_called=false on an empty table so the FIRST ticket is TKT-00001, and
-- is_called=true once rows exist so the next number is max+1.
SELECT setval('support_ticket_number_seq',
    GREATEST((SELECT COALESCE(MAX((regexp_replace(number, '\D', '', 'g'))::bigint), 0)
              FROM support_tickets WHERE number IS NOT NULL), 1),
    EXISTS (SELECT 1 FROM support_tickets WHERE number IS NOT NULL));

CREATE UNIQUE INDEX IF NOT EXISTS uq_support_tickets_number
    ON support_tickets(number) WHERE number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_support_tickets_company
    ON support_tickets (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status
    ON support_tickets (status, priority);

CREATE OR REPLACE FUNCTION assign_support_ticket_number() RETURNS trigger AS $$
BEGIN
    IF NEW.number IS NULL OR NEW.number = '' THEN
        NEW.number := 'TKT-' || lpad(nextval('support_ticket_number_seq')::text, 5, '0');
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_support_tickets_number ON support_tickets;
CREATE TRIGGER trg_support_tickets_number BEFORE INSERT ON support_tickets
    FOR EACH ROW EXECUTE FUNCTION assign_support_ticket_number();

DROP TRIGGER IF EXISTS trg_support_tickets_updated_at ON support_tickets;
CREATE TRIGGER trg_support_tickets_updated_at BEFORE UPDATE ON support_tickets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE support_tickets IS
'Support work item with the full lifecycle (open → in_progress → waiting_customer → resolved → closed, closed reopens to in_progress). A ticket may be linked to the chat conversation it came from; every platform-side mutation writes a platform audit row.';
