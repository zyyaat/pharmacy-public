// Support live chat + tickets (Phase T1, migration 33) — REST handlers.
//
// The split of responsibilities, kept identical on both realms:
//
//   REST   — the source of truth: every send/read/close/ticket mutation runs
//            inside a transaction that also maintains the unread counters,
//            the last-message preview and the per-side read pointers.
//   HUB    — support_hub.go: after COMMIT the same event is pushed to live
//            sockets. A dropped socket loses nothing (polling covers it).
//   EMAIL  — support_mailer.go: quiet-hours notification when the receiving
//            side has NO live socket and the throttle window has passed.
//
// Support is deliberately NEVER plan-gated: a suspended company must still
// reach support (same reasoning as the subscription recovery endpoints).
package handlers

import (
        "context"
        "encoding/base64"
        "encoding/json"
        "errors"
        "log"
        "net/http"
        "strings"
        "unicode/utf8"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"

        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
)

const (
        supportPreviewLength  = 160
        supportDefaultPage    = 50
        supportMaxPage        = 100
        supportListLimit      = 100
        supportMaxSubjectLen  = 200
)

// supportTenant resolves the company behind a pharmacy-realm principal
// (company users carry company_id; employees resolve through the cached
// pharmacy → company mapping). Empty means the request cannot be scoped —
// every handler must refuse.
func (h *Handler) supportTenant(c *gin.Context, principal *auth.Principal) string {
        companyID := h.companyIDForGate(c, principal)
        return companyID
}

// scanSupportConversation maps one conversations row (optionally joined to
// companies for the platform inbox).
type supportConvRow struct {
        ID                  string
        CompanyID           string
        Subject             string
        Status              string
        ClosedBy            *string
        LastMessageAt       *time.Time
        LastMessagePreview  string
        LastSenderRealm     *string
        PlatformUnread      int
        CompanyUnread       int
        PlatformLastRead    *string
        CompanyLastRead     *string
        CreatedAt           *time.Time
        UpdatedAt           *time.Time
        CompanyName         *string
        CompanyEmail        *string
}

func (r *supportConvRow) toModel() models.SupportConversation {
        return models.SupportConversation{
                ID:                        r.ID,
                CompanyID:                 r.CompanyID,
                Subject:                   r.Subject,
                Status:                    r.Status,
                ClosedBy:                  r.ClosedBy,
                LastMessageAt:             r.LastMessageAt,
                LastMessagePreview:        r.LastMessagePreview,
                PlatformUnreadCount:       r.PlatformUnread,
                CompanyUnreadCount:        r.CompanyUnread,
                PlatformLastReadMessageID: r.PlatformLastRead,
                CompanyLastReadMessageID:  r.CompanyLastRead,
                CreatedAt:                 r.CreatedAt,
                UpdatedAt:                 r.UpdatedAt,
                CompanyName:               r.CompanyName,
                CompanyEmail:              r.CompanyEmail,
        }
}

const supportConvColumns = `
    s.id::text, s.company_id::text, s.subject, s.status, s.closed_by,
    s.last_message_at, s.last_message_preview, s.last_sender_realm,
    s.platform_unread_count, s.company_unread_count,
    s.platform_last_read_message_id::text, s.company_last_read_message_id::text,
    s.created_at, s.updated_at`

// loadSupportConversationTx locks (FOR UPDATE when asked) and scans one
// conversation. errNoSupportRows signals 404 to the caller.
var errNoSupportRows = errors.New("support: row not found")

func loadSupportConversationTx(ctx context.Context, tx pgx.Tx, id, companyID string, forUpdate bool) (*supportConvRow, error) {
        q := `SELECT ` + supportConvColumns + `
        FROM support_conversations s WHERE s.id = $1::uuid`
        args := []any{id}
        if companyID != "" {
                q += ` AND s.company_id = $2::uuid`
                args = append(args, companyID)
        }
        if forUpdate {
                q += ` FOR UPDATE`
        }
        var row supportConvRow
        err := tx.QueryRow(ctx, q, args...).Scan(
                &row.ID, &row.CompanyID, &row.Subject, &row.Status, &row.ClosedBy,
                &row.LastMessageAt, &row.LastMessagePreview, &row.LastSenderRealm,
                &row.PlatformUnread, &row.CompanyUnread,
                &row.PlatformLastRead, &row.CompanyLastRead,
                &row.CreatedAt, &row.UpdatedAt,
        )
        if errors.Is(err, pgx.ErrNoRows) {
                return nil, errNoSupportRows
        }
        if err != nil {
                return nil, err
        }
        return &row, nil
}

// insertSupportMessageTx appends one message and maintains the conversation
// bookkeeping in the SAME transaction. System rows skip the preview/unread
// updates: the inbox order and counters answer "who owes a reply" and a
// lifecycle note is not a reply. Human rows bump last_message_at/preview +
// last_sender_realm and increment the OTHER side's counter.
func insertSupportMessageTx(
        ctx context.Context, tx pgx.Tx,
        conversationID, senderRealm, senderID, senderName, body string,
        attachmentID *string, isSystem bool, systemKind string,
) (*models.SupportMessage, error) {
        var msg models.SupportMessage
        var kind any
        if systemKind != "" {
                kind = systemKind
        }
        var attachment any
        if attachmentID != nil && *attachmentID != "" {
                attachment = *attachmentID
        }
        var sender any
        if senderID != "" {
                sender = senderID
        }
        err := tx.QueryRow(ctx, `
        INSERT INTO support_messages
            (conversation_id, sender_realm, sender_id, sender_name, body, attachment_id, is_system, system_kind)
        VALUES ($1::uuid, $2, NULLIF($3,'')::uuid, $4, $5, NULLIF($6,'')::uuid, $7, $8)
        RETURNING id::text, conversation_id::text, sender_realm, sender_id::text,
                  sender_name, body, attachment_id::text, is_system, system_kind, created_at
    `, conversationID, senderRealm, sender, senderName, body, attachment, isSystem, kind).Scan(
                &msg.ID, &msg.ConversationID, &msg.SenderRealm, &msg.SenderID,
                &msg.SenderName, &msg.Body, &msg.AttachmentID, &msg.IsSystem, &msg.SystemKind, &msg.CreatedAt,
        )
        if err != nil {
                return nil, err
        }
        if !isSystem {
                preview := body
                if preview == "" && attachmentID != nil {
                        preview = "(attachment)"
                }
                if len(preview) > supportPreviewLength {
                        preview = preview[:supportPreviewLength]
                }
                otherCounter := "platform_unread_count"
                if senderRealm == models.SupportSenderPlatform {
                        otherCounter = "company_unread_count"
                }
                if _, err := tx.Exec(ctx, `
            UPDATE support_conversations SET
                last_message_at = NOW(),
                last_message_preview = $2,
                last_sender_realm = $3,
                `+otherCounter+` = `+otherCounter+` + 1
            WHERE id = $1::uuid
        `, conversationID, preview, senderRealm); err != nil {
                        return nil, err
                }
        }
        return &msg, nil
}

// supportMessageJSON converts a messages row scan into the wire shape.
func scanSupportMessage(scan func(dest ...any) error) (*models.SupportMessage, error) {
        var m models.SupportMessage
        var systemKind *string
        if err := scan(&m.ID, &m.ConversationID, &m.SenderRealm, &m.SenderID, &m.SenderName,
                &m.Body, &m.AttachmentID, &m.IsSystem, &systemKind, &m.CreatedAt); err != nil {
                return nil, err
        }
        m.SystemKind = systemKind
        return &m, nil
}

// ---------------------------------------------------------------------------
// Overview counters (both realms)
// ---------------------------------------------------------------------------

func (h *Handler) supportOverviewPayload(ctx context.Context, companyID string) (gin.H, error) {
        var unread, openChats, openTickets, urgentTickets, unanswered int
        var platformOnline bool
        if companyID != "" {
                err := h.db.QueryRow(ctx, `
            SELECT
                COALESCE(SUM(company_unread_count), 0),
                COUNT(*) FILTER (WHERE status = 'open')
            FROM support_conversations WHERE company_id = $1::uuid
        `, companyID).Scan(&unread, &openChats)
                if err != nil {
                        return nil, err
                }
                err = h.db.QueryRow(ctx, `
            SELECT
                COUNT(*) FILTER (WHERE status NOT IN ('resolved', 'closed')),
                COUNT(*) FILTER (WHERE status NOT IN ('resolved', 'closed') AND priority = 'urgent')
            FROM support_tickets WHERE company_id = $1::uuid
        `, companyID).Scan(&openTickets, &urgentTickets)
                if err != nil {
                        return nil, err
                }
        } else {
                err := h.db.QueryRow(ctx, `
            SELECT
                COALESCE(SUM(platform_unread_count), 0),
                COUNT(*) FILTER (WHERE status = 'open'),
                COUNT(*) FILTER (WHERE status = 'open' AND last_sender_realm = 'pharmacy')
            FROM support_conversations
        `).Scan(&unread, &openChats, &unanswered)
                if err != nil {
                        return nil, err
                }
                err = h.db.QueryRow(ctx, `
            SELECT
                COUNT(*) FILTER (WHERE status NOT IN ('resolved', 'closed')),
                COUNT(*) FILTER (WHERE status NOT IN ('resolved', 'closed') AND priority = 'urgent')
            FROM support_tickets
        `).Scan(&openTickets, &urgentTickets)
                if err != nil {
                        return nil, err
                }
        }
        if h.supportHub != nil {
                platformOnline = h.supportHub.PlatformSupportOnline()
        }
        return gin.H{
                "unread_conversations":     unread,
                "open_conversations":       openChats,
                "unanswered_conversations": unanswered,
                "open_tickets":             openTickets,
                "urgent_tickets":           urgentTickets,
                "platform_online":          platformOnline,
        }, nil
}

// GetPharmacySupportOverview — the pharmacy sidebar badge + status dot.
func (h *Handler) GetPharmacySupportOverview(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        companyID := h.supportTenant(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        payload, err := h.supportOverviewPayload(c.Request.Context(), companyID)
        if err != nil {
                log.Printf("[support] support_overview_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_overview_failed"})
                return
        }
        c.JSON(http.StatusOK, payload)
}

// GetPlatformSupportOverview — the support dashboard cards.
func (h *Handler) GetPlatformSupportOverview(c *gin.Context) {
        payload, err := h.supportOverviewPayload(c.Request.Context(), "")
        if err != nil {
                log.Printf("[support] support_overview_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_overview_failed"})
                return
        }
        c.JSON(http.StatusOK, payload)
}

// ---------------------------------------------------------------------------
// Conversation lists
// ---------------------------------------------------------------------------

const supportListLimitSQL = ` LIMIT 100`

func (h *Handler) listConversations(c *gin.Context, companyID, filter string) {
        ctx := c.Request.Context()
        var rows pgx.Rows
        var err error
        if companyID != "" {
                // Company side: only its own channels, newest first. The joined
                // company columns are bound to NULL — one shared scan below.
                rows, err = h.db.Query(ctx, `
            SELECT `+supportConvColumns+`, NULL::text, NULL::text
            FROM support_conversations s
            WHERE s.company_id = $1::uuid
            ORDER BY s.last_message_at DESC`+supportListLimitSQL, companyID)
        } else {
                // Platform inbox: company identity joined, filters distinct:
                // unread (platform has unseen messages) vs unanswered (open and the
                // pharmacy wrote last) vs closed. Optional company_id scope.
                base := `SELECT ` + supportConvColumns + `, co.name, co.email
            FROM support_conversations s JOIN companies co ON co.id = s.company_id`
                scope := strings.TrimSpace(c.Query("company_id"))
                where := ` WHERE true`
                switch filter {
                case "unread":
                        where = ` WHERE s.platform_unread_count > 0`
                case "unanswered":
                        where = ` WHERE s.status = 'open' AND s.last_sender_realm = 'pharmacy'`
                case "closed":
                        where = ` WHERE s.status = 'closed'`
                }
                if scope != "" {
                        rows, err = h.db.Query(ctx, base+where+` AND s.company_id = $1::uuid
            ORDER BY s.last_message_at DESC`+supportListLimitSQL, scope)
                } else {
                        rows, err = h.db.Query(ctx, base+where+`
            ORDER BY s.last_message_at DESC`+supportListLimitSQL)
                }
        }
        if err != nil {
                log.Printf("[support] support_list_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_list_failed"})
                return
        }
        defer rows.Close()
        out := make([]models.SupportConversation, 0, 16)
        for rows.Next() {
                var row supportConvRow
                if err := rows.Scan(&row.ID, &row.CompanyID, &row.Subject, &row.Status, &row.ClosedBy,
                        &row.LastMessageAt, &row.LastMessagePreview, &row.LastSenderRealm,
                        &row.PlatformUnread, &row.CompanyUnread, &row.PlatformLastRead, &row.CompanyLastRead,
                        &row.CreatedAt, &row.UpdatedAt, &row.CompanyName, &row.CompanyEmail); err != nil {
                        log.Printf("[support] support_list_scan_failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "support_list_scan_failed"})
                        return
                }
                out = append(out, row.toModel())
        }
        if err := rows.Err(); err != nil {
                log.Printf("[support] support_list_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_list_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"conversations": out})
}

// ListPharmacySupportConversations — the company's own channels.
func (h *Handler) ListPharmacySupportConversations(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        companyID := h.supportTenant(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        h.listConversations(c, companyID, "all")
}

// ListPlatformSupportConversations — the support inbox with filters
// all|unread|unanswered|closed (+ optional company_id scope).
func (h *Handler) ListPlatformSupportConversations(c *gin.Context) {
        h.listConversations(c, "", strings.TrimSpace(c.DefaultQuery("filter", "all")))
}

// ---------------------------------------------------------------------------
// Conversation detail + messages
// ---------------------------------------------------------------------------

// supportConversationDetail loads the conversation (+ its latest ticket, if
// any) and the live-socket flags so both UIs can show a presence dot.
func (h *Handler) supportConversationDetail(c *gin.Context, companyID string) {
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                log.Printf("[support] support_detail_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_detail_failed"})
                return
        }
        defer tx.Rollback(ctx)
        row, err := loadSupportConversationTx(ctx, tx, c.Param("id"), companyID, false)
        if errors.Is(err, errNoSupportRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "conversation_not_found"})
                return
        }
        if err != nil {
                log.Printf("[support] support_detail_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_detail_failed"})
                return
        }
        var ticket *models.SupportTicket
        t, err := loadLatestTicketForConversationTx(ctx, tx, row.ID)
        if err != nil {
                log.Printf("[support] support_detail_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_detail_failed"})
                return
        }
        if t != nil {
                ticket = t
        }
        commitErr := tx.Commit(ctx)
        if commitErr != nil {
                log.Printf("[support] support_detail_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_detail_failed"})
                return
        }
        resp := gin.H{
                "conversation": row.toModel(),
                "ticket":       ticket,
        }
        if h.supportHub != nil {
                resp["platform_online"] = h.supportHub.PlatformSupportOnline()
                if companyID == "" {
                        resp["company_online"] = h.supportHub.CompanySupportOnline(row.CompanyID)
                } else {
                        resp["company_online"] = h.supportHub.CompanySupportOnline(companyID)
                }
        }
        c.JSON(http.StatusOK, resp)
}

// GetPharmacySupportConversation / GetPlatformSupportConversation.
func (h *Handler) GetPharmacySupportConversation(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        companyID := h.supportTenant(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        h.supportConversationDetail(c, companyID)
}

func (h *Handler) GetPlatformSupportConversation(c *gin.Context) {
        h.supportConversationDetail(c, "")
}

// listSupportMessages pages DESC (for the WHERE cursor) then returns ASC —
// the natural chat order. `before_ts`+`before_id` form the (created_at, id)
// row-comparison cursor; omit both for the newest page.
func (h *Handler) listSupportMessages(c *gin.Context, companyID string) {
        ctx := c.Request.Context()
        conversationID := c.Param("id")
        limit := supportDefaultPage
        if v := c.Query("limit"); v != "" {
                if n := parseIntDefault(v, supportDefaultPage); n >= 1 && n <= supportMaxPage {
                        limit = n
                }
        }
        // The company boundary rides along in the same query — a foreign id is
        // indistinguishable from a missing one (404, not 403).
        boundary := ""
        args := []any{conversationID}
        if companyID != "" {
                boundary = ` AND s.company_id = $2::uuid`
                args = append(args, companyID)
        }
        var exists bool
        check := `SELECT true FROM support_conversations s WHERE s.id = $1::uuid` + boundary
        if err := h.db.QueryRow(ctx, check, args...).Scan(&exists); err != nil {
                if errors.Is(err, pgx.ErrNoRows) {
                        c.JSON(http.StatusNotFound, gin.H{"error": "conversation_not_found"})
                        return
                }
                log.Printf("[support] support_messages_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_messages_failed"})
                return
        }

        msgArgs := []any{conversationID, limit + 1}
        cursor := ``
        if ts := strings.TrimSpace(c.Query("before_ts")); ts != "" {
                parsed, err := time.Parse(time.RFC3339Nano, ts)
                if err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_before_ts"})
                        return
                }
                cursor = ` AND (m.created_at, m.id) < ($3::timestamptz, COALESCE(NULLIF($4,'')::uuid, '00000000-0000-0000-0000-000000000000'::uuid))`
                msgArgs = append(msgArgs, parsed, strings.TrimSpace(c.Query("before_id")))
        }
        q := `
        SELECT m.id::text, m.conversation_id::text, m.sender_realm, m.sender_id::text,
               m.sender_name, m.body, m.attachment_id::text, m.is_system, m.system_kind, m.created_at
        FROM support_messages m
        WHERE m.conversation_id = $1::uuid` + cursor + `
        ORDER BY m.created_at DESC, m.id DESC
        LIMIT $2`
        rows, err := h.db.Query(ctx, q, msgArgs...)
        if err != nil {
                log.Printf("[support] support_messages_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_messages_failed"})
                return
        }
        defer rows.Close()
        page := make([]*models.SupportMessage, 0, limit)
        for rows.Next() {
                m, err := scanSupportMessage(rows.Scan)
                if err != nil {
                        log.Printf("[support] support_messages_scan_failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "support_messages_scan_failed"})
                        return
                }
                page = append(page, m)
        }
        if err := rows.Err(); err != nil {
                log.Printf("[support] support_messages_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_messages_failed"})
                return
        }
        hasMore := len(page) > limit
        if hasMore {
                page = page[:limit]
        }
        // reverse → ascending
        for i, j := 0, len(page)-1; i < j; i, j = i+1, j-1 {
                page[i], page[j] = page[j], page[i]
        }
        c.JSON(http.StatusOK, gin.H{"messages": page, "has_more": hasMore})
}

func (h *Handler) ListPharmacySupportMessages(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        companyID := h.supportTenant(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        h.listSupportMessages(c, companyID)
}

func (h *Handler) ListPlatformSupportMessages(c *gin.Context) {
        h.listSupportMessages(c, "")
}

func parseIntDefault(v string, def int) int {
        n := 0
        for _, r := range v {
                if r < '0' || r > '9' {
                        return def
                }
                n = n*10 + int(r-'0')
        }
        if n == 0 {
                return def
        }
        return n
}

// ---------------------------------------------------------------------------
// Create conversation (company side) — first message included
// ---------------------------------------------------------------------------

type supportCreateConversationBody struct {
        Subject      string  `json:"subject"`
        Body         string  `json:"body"`
        AttachmentID *string `json:"attachment_id"`
}

// CreatePharmacySupportConversation opens a channel with the platform.
// Subject is optional (defaulted) — friction-free first contact like every
// modern help desk; the first message is required.
func (h *Handler) CreatePharmacySupportConversation(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        companyID := h.supportTenant(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        var body supportCreateConversationBody
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body"})
                return
        }
        body.Body = strings.TrimSpace(body.Body)
        body.Subject = strings.TrimSpace(body.Subject)
        if body.Body == "" && body.AttachmentID == nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "message_required"})
                return
        }
        if utf8.RuneCountInString(body.Body) > models.SupportMaxMessageLength {
                c.JSON(http.StatusBadRequest, gin.H{"error": "message_too_long"})
                return
        }
        if len(body.Subject) > supportMaxSubjectLen {
                c.JSON(http.StatusBadRequest, gin.H{"error": "subject_too_long"})
                return
        }
        if body.Subject == "" {
                body.Subject = defaultSubjectFor(body.Body)
        }
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                log.Printf("[support] support_create_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_create_failed"})
                return
        }
        defer tx.Rollback(ctx)
        if body.AttachmentID != nil && *body.AttachmentID != "" {
                if err := ensureAttachmentUsableTx(ctx, tx, *body.AttachmentID, companyID, models.SupportSenderPharmacy); err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "attachment_invalid"})
                        return
                }
        }
        var convID string
        if err := tx.QueryRow(ctx, `
        INSERT INTO support_conversations (company_id, subject, status, last_sender_realm)
        VALUES ($1::uuid, $2, 'open', 'pharmacy')
        RETURNING id::text
    `, companyID, body.Subject).Scan(&convID); err != nil {
                log.Printf("[support] support_create_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_create_failed"})
                return
        }
        msg, err := insertSupportMessageTx(ctx, tx, convID, models.SupportSenderPharmacy,
                principal.ID, senderDisplayName(principal), body.Body, body.AttachmentID, false, "")
        if err != nil {
                log.Printf("[support] support_create_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_create_failed"})
                return
        }
        row, err := loadSupportConversationTx(ctx, tx, convID, "", false)
        if err != nil {
                log.Printf("[support] support_create_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_create_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                log.Printf("[support] support_create_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_create_failed"})
                return
        }
        // Post-commit: push to any live platform socket + quiet-hours mail.
        if h.supportHub != nil {
                if payload := marshalSupportEnvelope(supportEnvelope{
                        Type: "message.new", ConversationID: convID, CompanyID: companyID,
                        Message: mustJSON(msg),
                }); payload != nil {
                        h.supportHub.toPlatform(payload)
                }
        }
        h.supportNotifyMaybe(ctx, companyID, models.SupportSenderPharmacy, convID,
                senderDisplayName(principal), msg.Body)
        c.JSON(http.StatusCreated, gin.H{"conversation": row.toModel(), "message": msg})
}

// defaultSubjectFor derives a short subject from the first message —
// every big help desk does this so an empty subject never blocks contact.
func defaultSubjectFor(body string) string {
        trimmed := strings.TrimSpace(body)
        if len(trimmed) > 80 {
                trimmed = trimmed[:80]
        }
        if trimmed == "" {
                return "Support request"
        }
        return strings.ReplaceAll(trimmed, "\n", " ")
}

func senderDisplayName(principal *auth.Principal) string {
        if principal.DisplayName != "" {
                return principal.DisplayName
        }
        return principal.Email
}

func mustJSON(v any) json.RawMessage {
        blob, err := json.Marshal(v)
        if err != nil {
                return nil
        }
        return blob
}

// ---------------------------------------------------------------------------
// Send message (both realms) — the guarded hot path
// ---------------------------------------------------------------------------

type supportSendMessageBody struct {
        Body         string  `json:"body"`
        AttachmentID *string `json:"attachment_id"`
}

// sendSupportMessage is the shared write path: load + lock the conversation,
// reject closed channels for HUMAN messages (system rows bypass this helper),
// validate the attachment, insert + maintain counters, commit, push, mail.
func (h *Handler) sendSupportMessage(c *gin.Context, companyID, realm string) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        var body supportSendMessageBody
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body"})
                return
        }
        body.Body = strings.TrimSpace(body.Body)
        if body.Body == "" && body.AttachmentID == nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "message_required"})
                return
        }
        if utf8.RuneCountInString(body.Body) > models.SupportMaxMessageLength {
                c.JSON(http.StatusBadRequest, gin.H{"error": "message_too_long"})
                return
        }
        if realm == models.SupportSenderPharmacy && companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                log.Printf("[support] support_send_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_send_failed"})
                return
        }
        defer tx.Rollback(ctx)
        row, err := loadSupportConversationTx(ctx, tx, c.Param("id"), companyID, true)
        if errors.Is(err, errNoSupportRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "conversation_not_found"})
                return
        }
        if err != nil {
                log.Printf("[support] support_send_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_send_failed"})
                return
        }
        if row.Status == models.SupportConversationClosed {
                c.JSON(http.StatusConflict, gin.H{"error": "conversation_closed"})
                return
        }
        if body.AttachmentID != nil && *body.AttachmentID != "" {
                if err := ensureAttachmentUsableTx(ctx, tx, *body.AttachmentID, row.CompanyID, realm); err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "attachment_invalid"})
                        return
                }
        }
        msg, err := insertSupportMessageTx(ctx, tx, row.ID, realm,
                principal.ID, senderDisplayName(principal), body.Body, body.AttachmentID, false, "")
        if err != nil {
                log.Printf("[support] support_send_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_send_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                log.Printf("[support] support_send_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_send_failed"})
                return
        }
        if h.supportHub != nil {
                if payload := marshalSupportEnvelope(supportEnvelope{
                        Type: "message.new", ConversationID: row.ID, CompanyID: row.CompanyID,
                        Message: mustJSON(msg),
                }); payload != nil {
                        h.supportHub.toBoth(row.CompanyID, payload)
                }
        }
        h.supportNotifyMaybe(ctx, row.CompanyID, realm, row.ID, senderDisplayName(principal), msg.Body)
        c.JSON(http.StatusCreated, gin.H{"message": msg})
}

func (h *Handler) SendPharmacySupportMessage(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        h.sendSupportMessage(c, h.supportTenant(c, principal), models.SupportSenderPharmacy)
}

func (h *Handler) SendPlatformSupportMessage(c *gin.Context) {
        h.sendSupportMessage(c, "", models.SupportSenderPlatform)
}

// ---------------------------------------------------------------------------
// Mark read (both realms) — clears THIS side's counter under row lock
// ---------------------------------------------------------------------------

// markSupportRead sets the caller side's read pointer to the newest message
// and zeroes its counter. FOR UPDATE serializes against a concurrent send so
// a message arriving mid-transaction is never silently swallowed.
func (h *Handler) markSupportRead(c *gin.Context, companyID, realm string) {
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                log.Printf("[support] support_read_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_read_failed"})
                return
        }
        defer tx.Rollback(ctx)
        row, err := loadSupportConversationTx(ctx, tx, c.Param("id"), companyID, true)
        if errors.Is(err, errNoSupportRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "conversation_not_found"})
                return
        }
        if err != nil {
                log.Printf("[support] support_read_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_read_failed"})
                return
        }
        var latest string
        if err := tx.QueryRow(ctx, `
        SELECT id::text FROM support_messages
        WHERE conversation_id = $1::uuid
        ORDER BY created_at DESC, id DESC LIMIT 1
    `, row.ID).Scan(&latest); err != nil && !errors.Is(err, pgx.ErrNoRows) {
                log.Printf("[support] support_read_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_read_failed"})
                return
        }
        if latest != "" {
                counter, pointer := "platform_unread_count", "platform_last_read_message_id"
                if realm == models.SupportSenderPharmacy {
                        counter, pointer = "company_unread_count", "company_last_read_message_id"
                }
                if _, err := tx.Exec(ctx, `
            UPDATE support_conversations SET
                `+pointer+` = $2::uuid,
                `+counter+` = 0
            WHERE id = $1::uuid
        `, row.ID, latest); err != nil {
                        log.Printf("[support] support_read_failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "support_read_failed"})
                        return
                }
        }
        if err := tx.Commit(ctx); err != nil {
                log.Printf("[support] support_read_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_read_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (h *Handler) MarkPharmacySupportRead(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        h.markSupportRead(c, h.supportTenant(c, principal), models.SupportSenderPharmacy)
}

func (h *Handler) MarkPlatformSupportRead(c *gin.Context) {
        h.markSupportRead(c, "", models.SupportSenderPlatform)
}

// ---------------------------------------------------------------------------
// Close conversation (both realms) — a system message records who closed it
// ---------------------------------------------------------------------------

// closeSupportConversation closes the channel. Closing is a lifecycle event,
// not a deletion: history stays readable for both sides forever; further
// HUMAN messages are rejected with 409 while system rows keep flowing (a
// linked ticket may still resolve afterwards).
func (h *Handler) closeSupportConversation(c *gin.Context, companyID, realm string) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                log.Printf("[support] support_close_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_close_failed"})
                return
        }
        defer tx.Rollback(ctx)
        row, err := loadSupportConversationTx(ctx, tx, c.Param("id"), companyID, true)
        if errors.Is(err, errNoSupportRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "conversation_not_found"})
                return
        }
        if err != nil {
                log.Printf("[support] support_close_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_close_failed"})
                return
        }
        if row.Status == models.SupportConversationClosed {
                c.JSON(http.StatusConflict, gin.H{"error": "conversation_already_closed"})
                return
        }
        if _, err := tx.Exec(ctx, `
        UPDATE support_conversations SET status = 'closed', closed_by = $2 WHERE id = $1::uuid
    `, row.ID, realm); err != nil {
                log.Printf("[support] support_close_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_close_failed"})
                return
        }
        msg, err := insertSupportMessageTx(ctx, tx, row.ID, realm,
                principal.ID, senderDisplayName(principal),
                closeSystemText(realm, principal), nil, true, models.SupportSystemConversationClosed)
        if err != nil {
                log.Printf("[support] support_close_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_close_failed"})
                return
        }
        row, err = loadSupportConversationTx(ctx, tx, row.ID, "", false)
        if err != nil {
                log.Printf("[support] support_close_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_close_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                log.Printf("[support] support_close_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "support_close_failed"})
                return
        }
        if h.supportHub != nil {
                if payload := marshalSupportEnvelope(supportEnvelope{
                        Type: "conversation.updated", ConversationID: row.ID, CompanyID: row.CompanyID,
                }); payload != nil {
                        h.supportHub.toBoth(row.CompanyID, payload)
                }
                if payload := marshalSupportEnvelope(supportEnvelope{
                        Type: "message.new", ConversationID: row.ID, CompanyID: row.CompanyID,
                        Message: mustJSON(msg),
                }); payload != nil {
                        h.supportHub.toBoth(row.CompanyID, payload)
                }
        }
        c.JSON(http.StatusOK, gin.H{"conversation": row.toModel()})
}

func closeSystemText(realm string, principal *auth.Principal) string {
        if realm == models.SupportSenderPlatform {
                return "أُغلقت المحادثة من فريق الدعم — " + senderDisplayName(principal)
        }
        return "أُغلقت المحادثة من الشركة — " + senderDisplayName(principal)
}

func (h *Handler) ClosePharmacySupportConversation(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        h.closeSupportConversation(c, h.supportTenant(c, principal), models.SupportSenderPharmacy)
}

func (h *Handler) ClosePlatformSupportConversation(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal == nil {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        h.closeSupportConversation(c, "", models.SupportSenderPlatform)
}

// ---------------------------------------------------------------------------
// Attachments — upload then reference from a message (both realms)
// ---------------------------------------------------------------------------

// ensureAttachmentUsableTx guards the reference step: the attachment must
// exist, belong to the same company, come from the same realm, and not
// already be attached to a message (a bytea row is single-use — no silent
// sharing of one upload across conversations).
func ensureAttachmentUsableTx(ctx context.Context, tx pgx.Tx, attachmentID, companyID, realm string) error {
        var ownerCompany, ownerRealm string
        var used bool
        err := tx.QueryRow(ctx, `
        SELECT a.company_id::text, a.uploaded_by_realm,
               EXISTS (SELECT 1 FROM support_messages m WHERE m.attachment_id = a.id)
        FROM support_attachments a WHERE a.id = $1::uuid
    `, attachmentID).Scan(&ownerCompany, &ownerRealm, &used)
        if errors.Is(err, pgx.ErrNoRows) {
                return errors.New("attachment missing")
        }
        if err != nil {
                return err
        }
        if used {
                return errors.New("attachment already used")
        }
        if ownerCompany != companyID {
                return errors.New("attachment foreign company")
        }
        if ownerRealm != realm {
                return errors.New("attachment foreign realm")
        }
        return nil
}

type supportUploadBody struct {
        FileName string `json:"file_name"`
        MimeType string `json:"mime_type"`
        Content  string `json:"content"` // base64 or a data: URL
        // Platform uploads must name the OWNING company (the conversation the
        // file will be sent in); the pharmacy path fills it from the principal.
        CompanyID string `json:"company_id"`
}

// uploadSupportAttachment validates + stores one small file. Strictness is
// the point: 2 MiB hard ceiling (DB CHECK too), four mime types support
// actually needs, path-stripped names. Content rides base64 because there
// is no object storage in this stack — the honest v1.
func (h *Handler) uploadSupportAttachment(c *gin.Context, companyID, realm string) {
        // The body is bound EXACTLY ONCE by the caller (gin consumes the request
        // reader on the first ShouldBindJSON — a second bind reads EOF).
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal == nil {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        var body supportUploadBody
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body"})
                return
        }
        h.storeSupportAttachment(c, principal, companyID, realm, body)
}

// storeSupportAttachment validates + persists one already-bound upload.
// principal may be nil for the platform path — uploaded_by stays NULL then.
func (h *Handler) storeSupportAttachment(c *gin.Context, principal *auth.Principal, companyID, realm string, body supportUploadBody) {
        var uploaderID string
        if principal != nil {
                uploaderID = principal.ID
        }
        mimeType := strings.ToLower(strings.TrimSpace(body.MimeType))
        ext, allowed := models.SupportAttachmentMIMEs[mimeType]
        if !allowed {
                c.JSON(http.StatusUnsupportedMediaType, gin.H{"error": "mime_not_allowed"})
                return
        }
        // Accept both raw base64 and data URLs the browser produces.
        content := strings.TrimSpace(body.Content)
        if i := strings.Index(content, "base64,"); i >= 0 && strings.HasPrefix(content, "data:") {
                content = content[i+len("base64,"):]
        }
        raw, err := base64.StdEncoding.DecodeString(content)
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "content_not_base64"})
                return
        }
        if len(raw) == 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "content_empty"})
                return
        }
        if len(raw) > models.SupportMaxAttachmentBytes {
                c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "file_too_large"})
                return
        }
        fileName := sanitizeSupportFileName(body.FileName, ext)
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                log.Printf("[support] upload_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "upload_failed"})
                return
        }
        defer tx.Rollback(ctx)
        var id string
        if err := tx.QueryRow(ctx, `
        INSERT INTO support_attachments
            (company_id, uploaded_by_realm, uploaded_by, file_name, mime_type, size_bytes, content)
        VALUES (NULLIF($1,'')::uuid, $2, NULLIF($3,'')::uuid, $4, $5, $6, $7)
        RETURNING id::text
    `, companyID, realm, uploaderID, fileName, mimeType, len(raw), raw).Scan(&id); err != nil {
                log.Printf("[support] upload_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "upload_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                log.Printf("[support] upload_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "upload_failed"})
                return
        }
        c.JSON(http.StatusCreated, gin.H{"attachment": models.SupportAttachmentMeta{
                ID: id, FileName: fileName, MimeType: mimeType, SizeBytes: int64(len(raw)),
        }})
}

func (h *Handler) UploadPharmacySupportAttachment(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        companyID := h.supportTenant(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        h.uploadSupportAttachment(c, companyID, models.SupportSenderPharmacy)
}

func (h *Handler) UploadPlatformSupportAttachment(c *gin.Context) {
        // The platform uploads INTO a company context: the conversation it will
        // reply in decides the owning company (body must carry it) — every read
        // and every send-time validation stays company-scoped.
        var body supportUploadBody
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body"})
                return
        }
        if strings.TrimSpace(body.CompanyID) == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "company_required"})
                return
        }
        h.storeSupportAttachment(c, nil, strings.TrimSpace(body.CompanyID), models.SupportSenderPlatform, body)
}

// downloadSupportAttachment streams the bytes. Company callers are scoped
// to their own rows; platform callers may read any support attachment.
func (h *Handler) downloadSupportAttachment(c *gin.Context, companyID string) {
        ctx := c.Request.Context()
        q := `SELECT file_name, mime_type, content FROM support_attachments WHERE id = $1::uuid`
        args := []any{c.Param("id")}
        if companyID != "" {
                q += ` AND company_id = $2::uuid`
                args = append(args, companyID)
        }
        var fileName, mimeType string
        var content []byte
        err := h.db.QueryRow(ctx, q, args...).Scan(&fileName, &mimeType, &content)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "attachment_not_found"})
                return
        }
        if err != nil {
                log.Printf("[support] attachment_download_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "attachment_download_failed"})
                return
        }
        c.Header("Content-Disposition", `inline; filename="`+fileName+`"`)
        c.Data(http.StatusOK, mimeType, content)
}

func (h *Handler) GetPharmacySupportAttachment(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        companyID := h.supportTenant(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_required"})
                return
        }
        h.downloadSupportAttachment(c, companyID)
}

func (h *Handler) GetPlatformSupportAttachment(c *gin.Context) {
        h.downloadSupportAttachment(c, "")
}

// sanitizeSupportFileName strips any path components and caps the length,
// forcing the extension to match the validated mime type.
func sanitizeSupportFileName(name, ext string) string {
        name = strings.TrimSpace(name)
        if i := strings.LastIndexAny(name, `/\`); i >= 0 {
                name = name[i+1:]
        }
        name = strings.Map(func(r rune) rune {
                if r < 32 || r == '"' {
                        return '_'
                }
                return r
        }, name)
        if name == "" {
                name = "attachment" + ext
        }
        if len(name) > 200 {
                name = name[len(name)-200:]
        }
        // Keep the original extension only when it already matches the mime;
        // otherwise append the canonical one.
        if !strings.HasSuffix(strings.ToLower(name), ext) {
                name += ext
        }
        return name
}
