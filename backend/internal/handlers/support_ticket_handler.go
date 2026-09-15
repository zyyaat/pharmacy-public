// Support tickets (Phase T1) — the work item that outlives the chat.
//
// Lifecycle (locked by supportTicketTransitions):
//
//   open → in_progress → resolved → closed, with in_progress ⇄
//   waiting_customer and reopen from resolved/closed back to in_progress.
//
// Every platform-side mutation is: validated transition → transactional
// update → system message inside the linked conversation (both sides see
// one history) → platform audit row (who/when/what) → hub push. The chat
// itself is the customer-facing record; the audit log is the internal one.
//
// Company-side actions (create) need no RBAC permission — support is
// available to every principal, including locked-out companies. Their
// create audit is the ticket row + the chat history itself (tenant
// audit_logs requires a pharmacy scope that company-user principals do
// not carry — the same platform-vs-tenant split as migration 30).
package handlers

import (
        "context"
        "errors"
        "log"
        "net/http"
        "strings"
	"unicode/utf8"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"

        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
)

// supportTicketTransitions is the state machine. Terminal `closed` can only
// reopen to in_progress (a customer answered after closure — the professional
// desk reopens, never dead-ends).
var supportTicketTransitions = map[string][]string{
        models.SupportTicketOpen:            {models.SupportTicketInProgress, models.SupportTicketResolved, models.SupportTicketClosed},
        models.SupportTicketInProgress:      {models.SupportTicketWaitingCustomer, models.SupportTicketResolved, models.SupportTicketClosed},
        models.SupportTicketWaitingCustomer: {models.SupportTicketInProgress, models.SupportTicketResolved, models.SupportTicketClosed},
        models.SupportTicketResolved:        {models.SupportTicketClosed, models.SupportTicketInProgress},
        models.SupportTicketClosed:          {models.SupportTicketInProgress},
}

func supportTicketAllowed(from, to string) bool {
        for _, next := range supportTicketTransitions[from] {
                if next == to {
                        return true
                }
        }
        return false
}

// loadLatestTicketForConversationTx — the conversation detail shows the
// newest ticket linked to the channel (a channel may outlive several
// tickets; the newest is the live one). No ticket → (nil, nil).
func loadLatestTicketForConversationTx(ctx context.Context, tx pgx.Tx, conversationID string) (*models.SupportTicket, error) {
        var t models.SupportTicket
        err := tx.QueryRow(ctx, `
        SELECT t.id::text, t.company_id::text, t.conversation_id::text, t.number,
               t.subject, t.status, t.priority, t.category, t.assigned_to::text,
               t.resolution_note, t.resolved_at, t.closed_at, t.created_at, t.updated_at,
               co.name
        FROM support_tickets t JOIN companies co ON co.id = t.company_id
        WHERE t.conversation_id = $1::uuid
        ORDER BY t.created_at DESC, t.id DESC
        LIMIT 1
    `, conversationID).Scan(
                &t.ID, &t.CompanyID, &t.ConversationID, &t.Number,
                &t.Subject, &t.Status, &t.Priority, &t.Category, &t.AssignedTo,
                &t.ResolutionNote, &t.ResolvedAt, &t.ClosedAt, &t.CreatedAt, &t.UpdatedAt,
                &t.CompanyName,
        )
        if errors.Is(err, pgx.ErrNoRows) {
                return nil, nil
        }
        if err != nil {
                return nil, err
        }
        return &t, nil
}

// ---------------------------------------------------------------------------
// Company side — create + list own tickets
// ---------------------------------------------------------------------------

type supportCreateTicketBody struct {
        Subject        string  `json:"subject"`
        Category       string  `json:"category"`
        Priority       string  `json:"priority"`
        Body           string  `json:"body"`
        ConversationID *string `json:"conversation_id"`
}

func normalizeTicketCategory(v string) (string, bool) {
        switch strings.TrimSpace(v) {
        case "":
                return models.SupportCategoryOther, true
        case models.SupportCategoryBilling, models.SupportCategoryTechnical, models.SupportCategoryInventory,
                models.SupportCategoryAccount, models.SupportCategoryFeatureRequest, models.SupportCategoryOther:
                return strings.TrimSpace(v), true
        }
        return "", false
}

func normalizeTicketPriority(v string) (string, bool) {
        switch strings.TrimSpace(v) {
        case "":
                return models.SupportPriorityNormal, true
        case models.SupportPriorityLow, models.SupportPriorityNormal, models.SupportPriorityHigh, models.SupportPriorityUrgent:
                return strings.TrimSpace(v), true
        }
        return "", false
}

// CreatePharmacySupportTicket — from a conversation (escalate this chat) or
// standalone. With a body and no conversation the handler opens the chat
// thread itself: every ticket gets a conversation to live in.
func (h *Handler) CreatePharmacySupportTicket(c *gin.Context) {
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
        var body supportCreateTicketBody
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body"})
                return
        }
        body.Subject = strings.TrimSpace(body.Subject)
        body.Body = strings.TrimSpace(body.Body)
        if body.Subject == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "subject_required"})
                return
        }
        if len(body.Subject) > supportMaxSubjectLen {
                c.JSON(http.StatusBadRequest, gin.H{"error": "subject_too_long"})
                return
        }
        if utf8.RuneCountInString(body.Body) > models.SupportMaxMessageLength {
                c.JSON(http.StatusBadRequest, gin.H{"error": "message_too_long"})
                return
        }
        category, okC := normalizeTicketCategory(body.Category)
        if !okC {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_category"})
                return
        }
        priority, okP := normalizeTicketPriority(body.Priority)
        if !okP {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_priority"})
                return
        }
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                log.Printf("[support] ticket_create_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_create_failed"})
                return
        }
        defer tx.Rollback(ctx)

        conversationID := ""
        if body.ConversationID != nil && strings.TrimSpace(*body.ConversationID) != "" {
                // Escalate an existing chat — must belong to this company.
                row, err := loadSupportConversationTx(ctx, tx, strings.TrimSpace(*body.ConversationID), companyID, true)
                if errors.Is(err, errNoSupportRows) {
                        c.JSON(http.StatusNotFound, gin.H{"error": "conversation_not_found"})
                        return
                }
                if err != nil {
                        log.Printf("[support] ticket_create_failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_create_failed"})
                        return
                }
                conversationID = row.ID
        } else if body.Body != "" {
                // Standalone ticket with a first message → open the chat thread.
                subject := body.Subject
                var convID string
                if err := tx.QueryRow(ctx, `
            INSERT INTO support_conversations (company_id, subject, status, last_sender_realm)
            VALUES ($1::uuid, $2, 'open', 'pharmacy')
            RETURNING id::text
        `, companyID, subject).Scan(&convID); err != nil {
                        log.Printf("[support] ticket_create_failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_create_failed"})
                        return
                }
                if _, err := insertSupportMessageTx(ctx, tx, convID, models.SupportSenderPharmacy,
                        principal.ID, senderDisplayName(principal), body.Body, nil, false, ""); err != nil {
                        log.Printf("[support] ticket_create_failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_create_failed"})
                        return
                }
                conversationID = convID
        }

        var convArg any
        if conversationID != "" {
                convArg = conversationID
        }
        var t models.SupportTicket
        if err := tx.QueryRow(ctx, `
        INSERT INTO support_tickets
            (company_id, conversation_id, subject, status, priority, category)
        VALUES ($1::uuid, NULLIF($2,'')::uuid, $3, 'open', $4, $5)
        RETURNING id::text, company_id::text, conversation_id::text, number,
                  subject, status, priority, category, assigned_to::text,
                  resolution_note, resolved_at, closed_at, created_at, updated_at
    `, companyID, convArg, body.Subject, priority, category).Scan(
                &t.ID, &t.CompanyID, &t.ConversationID, &t.Number,
                &t.Subject, &t.Status, &t.Priority, &t.Category, &t.AssignedTo,
                &t.ResolutionNote, &t.ResolvedAt, &t.ClosedAt, &t.CreatedAt, &t.UpdatedAt,
        ); err != nil {
                log.Printf("[support] ticket_create_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_create_failed"})
                return
        }
        if conversationID != "" {
                if _, err := insertSupportMessageTx(ctx, tx, conversationID, models.SupportSenderPharmacy,
                        principal.ID, senderDisplayName(principal),
                        "تم إنشاء تذكرة "+t.Number+" من هذه المحادثة: "+t.Subject,
                        nil, true, models.SupportSystemTicketCreated); err != nil {
                        log.Printf("[support] ticket_create_failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_create_failed"})
                        return
                }
        }
        if err := tx.Commit(ctx); err != nil {
                log.Printf("[support] ticket_create_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_create_failed"})
                return
        }
        if conversationID != "" && h.supportHub != nil {
                if payload := marshalSupportEnvelope(supportEnvelope{
                        Type: "ticket.updated", CompanyID: companyID, Ticket: mustJSON(&t),
                }); payload != nil {
                        h.supportHub.toBoth(companyID, payload)
                }
        }
        c.JSON(http.StatusCreated, gin.H{"ticket": t})
}

// ListPharmacySupportTickets — the company's own tickets.
func (h *Handler) ListPharmacySupportTickets(c *gin.Context) {
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
        h.listTickets(c, companyID)
}

// ListPlatformSupportTickets — the platform work table with filters.
func (h *Handler) ListPlatformSupportTickets(c *gin.Context) {
        h.listTickets(c, "")
}

func (h *Handler) listTickets(c *gin.Context, companyID string) {
        ctx := c.Request.Context()
        q := `
        SELECT t.id::text, t.company_id::text, t.conversation_id::text, t.number,
               t.subject, t.status, t.priority, t.category, t.assigned_to::text,
               t.resolution_note, t.resolved_at, t.closed_at, t.created_at, t.updated_at,
               co.name
        FROM support_tickets t JOIN companies co ON co.id = t.company_id
        WHERE true`
        var args []any
        if companyID != "" {
                args = append(args, companyID)
                q += ` AND t.company_id = $1::uuid`
        }
        if v := strings.TrimSpace(c.Query("status")); v != "" && v != "all" {
                switch v {
                case "active":
                        q += ` AND t.status NOT IN ('resolved', 'closed')`
                default:
                        args = append(args, v)
                        q += ` AND t.status = $` + itoaLen(len(args))
                }
        }
        if v := strings.TrimSpace(c.Query("priority")); v != "" && v != "all" {
                args = append(args, v)
                q += ` AND t.priority = $` + itoaLen(len(args))
        }
        if v := strings.TrimSpace(c.Query("category")); v != "" && v != "all" {
                args = append(args, v)
                q += ` AND t.category = $` + itoaLen(len(args))
        }
        if companyID == "" {
                if v := strings.TrimSpace(c.Query("company_id")); v != "" {
                        args = append(args, v)
                        q += ` AND t.company_id = $` + itoaLen(len(args)) + `::uuid`
                }
        }
        q += ` ORDER BY CASE t.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END,
        t.created_at DESC LIMIT 200`
        rows, err := h.db.Query(ctx, q, args...)
        if err != nil {
                log.Printf("[support] ticket_list_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_list_failed"})
                return
        }
        defer rows.Close()
        out := make([]models.SupportTicket, 0, 16)
        for rows.Next() {
                var t models.SupportTicket
                if err := rows.Scan(&t.ID, &t.CompanyID, &t.ConversationID, &t.Number,
                        &t.Subject, &t.Status, &t.Priority, &t.Category, &t.AssignedTo,
                        &t.ResolutionNote, &t.ResolvedAt, &t.ClosedAt, &t.CreatedAt, &t.UpdatedAt,
                        &t.CompanyName); err != nil {
                        log.Printf("[support] ticket_list_scan_failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_list_scan_failed"})
                        return
                }
                out = append(out, t)
        }
        if err := rows.Err(); err != nil {
                log.Printf("[support] ticket_list_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_list_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"tickets": out})
}

func itoaLen(n int) string {
        digits := []byte{}
        if n == 0 {
                return "0"
        }
        for n > 0 {
                digits = append([]byte{byte('0' + n%10)}, digits...)
                n /= 10
        }
        return string(digits)
}

// ---------------------------------------------------------------------------
// Platform side — the audited lifecycle PATCH
// ---------------------------------------------------------------------------

type supportUpdateTicketBody struct {
        Status         *string `json:"status"`
        Priority       *string `json:"priority"`
        Category       *string `json:"category"`
        ResolutionNote *string `json:"resolution_note"`
}

// ticketSystemText renders the customer-visible note for a lifecycle change.
func ticketSystemText(kind, field, from, to string) string {
        switch kind {
        case models.SupportSystemTicketResolved:
                return "تم حل التذكرة بواسطة فريق الدعم"
        case models.SupportSystemTicketReopened:
                return "أُعيد فتح التذكرة بواسطة فريق الدعم"
        default:
                return "تم تحديث التذكرة (" + field + ": " + from + " ← " + to + ") بواسطة فريق الدعم"
        }
}

// UpdatePlatformSupportTicket applies guarded lifecycle changes. Each
// accepted change produces: transactional update + system chat message (if
// the ticket lives in a conversation) + platform audit row + hub push.
// Invalid transitions answer 409 with the allowed targets — the UI never
// has to guess.
func (h *Handler) UpdatePlatformSupportTicket(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok {
                c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
                return
        }
        var body supportUpdateTicketBody
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body"})
                return
        }
        if body.Status == nil && body.Priority == nil && body.Category == nil && body.ResolutionNote == nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "nothing_to_update"})
                return
        }
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                log.Printf("[support] ticket_update_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_update_failed"})
                return
        }
        defer tx.Rollback(ctx)

        // Lock the ticket row.
        var currentStatus, currentPriority, currentCategory string
        var conversationID *string
        lock := `
        SELECT status, priority, category, conversation_id::text
        FROM support_tickets WHERE id = $1::uuid`
        if err := tx.QueryRow(ctx, lock, c.Param("id")).Scan(
                &currentStatus, &currentPriority, &currentCategory, &conversationID,
        ); err != nil {
                if errors.Is(err, pgx.ErrNoRows) {
                        c.JSON(http.StatusNotFound, gin.H{"error": "ticket_not_found"})
                        return
                }
                log.Printf("[support] ticket_update_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_update_failed"})
                return
        }

        sets := []string{"updated_at = NOW()"}
        args := []any{c.Param("id")}
        // The NEXT placeholder index (args[0] is the WHERE id = $1 anchor) —
        // evaluated BEFORE the value is appended so indexes never collide.
        param := func() string { return itoaLen(len(args) + 1) }
        systemNotes := make([]gin.H, 0, 3)

        if body.Status != nil && *body.Status != currentStatus {
                to := strings.TrimSpace(*body.Status)
                switch to {
                case models.SupportTicketOpen, models.SupportTicketInProgress, models.SupportTicketWaitingCustomer,
                        models.SupportTicketResolved, models.SupportTicketClosed:
                default:
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status"})
                        return
                }
                if !supportTicketAllowed(currentStatus, to) {
                        c.JSON(http.StatusConflict, gin.H{
                                "error":    "invalid_transition",
                                "from":     currentStatus,
                                "allowed":  supportTicketTransitions[currentStatus],
                        })
                        return
                }
                sets = append(sets, "status = $"+param())
                args = append(args, to)
                kind := models.SupportSystemTicketUpdated
                if to == models.SupportTicketResolved {
                        sets = append(sets, "resolved_at = NOW()", "closed_at = NULL")
                        kind = models.SupportSystemTicketResolved
                } else if to == models.SupportTicketClosed {
                        sets = append(sets, "closed_at = NOW()")
                } else {
                        // Any active state re-clears the resolution stamps — a reopened
                        // ticket is an open ticket, period.
                        sets = append(sets, "resolved_at = NULL", "closed_at = NULL")
                        if currentStatus == models.SupportTicketResolved || currentStatus == models.SupportTicketClosed {
                                kind = models.SupportSystemTicketReopened
                        }
                }
                systemNotes = append(systemNotes, gin.H{"kind": kind, "text": ticketSystemText(kind, "status", currentStatus, to)})
        }
        if body.Priority != nil && *body.Priority != currentPriority {
                p, okP := normalizeTicketPriority(*body.Priority)
                if !okP {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_priority"})
                        return
                }
                sets = append(sets, "priority = $"+param())
                args = append(args, p)
                systemNotes = append(systemNotes, gin.H{"kind": models.SupportSystemTicketUpdated,
                        "text": ticketSystemText(models.SupportSystemTicketUpdated, "priority", currentPriority, p)})
        }
        if body.Category != nil && *body.Category != currentCategory {
                cat, okC := normalizeTicketCategory(*body.Category)
                if !okC {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_category"})
                        return
                }
                sets = append(sets, "category = $"+param())
                args = append(args, cat)
                systemNotes = append(systemNotes, gin.H{"kind": models.SupportSystemTicketUpdated,
                        "text": ticketSystemText(models.SupportSystemTicketUpdated, "category", currentCategory, cat)})
        }
        if body.ResolutionNote != nil {
                note := strings.TrimSpace(*body.ResolutionNote)
                if utf8.RuneCountInString(note) > 4000 {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "note_too_long"})
                        return
                }
                if note == "" {
                        sets = append(sets, "resolution_note = NULL")
                } else {
                        sets = append(sets, "resolution_note = $"+param())
                        args = append(args, note)
                }
        }

        update := `UPDATE support_tickets SET `
        for i, s := range sets {
                if i > 0 {
                        update += ", "
                }
                update += s
        }
        update += ` WHERE id = $1::uuid`
        if _, err := tx.Exec(ctx, update, args...); err != nil {
                log.Printf("[support] ticket_update_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_update_failed"})
                return
        }

        // Re-read the full row (with the company join) for the response.
        var fresh models.SupportTicket
        if err := tx.QueryRow(ctx, `
        SELECT t.id::text, t.company_id::text, t.conversation_id::text, t.number,
               t.subject, t.status, t.priority, t.category, t.assigned_to::text,
               t.resolution_note, t.resolved_at, t.closed_at, t.created_at, t.updated_at,
               co.name
        FROM support_tickets t JOIN companies co ON co.id = t.company_id
        WHERE t.id = $1::uuid
    `, c.Param("id")).Scan(
                &fresh.ID, &fresh.CompanyID, &fresh.ConversationID, &fresh.Number,
                &fresh.Subject, &fresh.Status, &fresh.Priority, &fresh.Category, &fresh.AssignedTo,
                &fresh.ResolutionNote, &fresh.ResolvedAt, &fresh.ClosedAt, &fresh.CreatedAt, &fresh.UpdatedAt,
                &fresh.CompanyName,
        ); err != nil {
                log.Printf("[support] ticket_update_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_update_failed"})
                return
        }

        // System messages into the linked conversation (both histories align).
        convID := ""
        if conversationID != nil {
                convID = *conversationID
        }
        messages := make([]*models.SupportMessage, 0, len(systemNotes))
        if convID != "" {
                for _, note := range systemNotes {
                        msg, err := insertSupportMessageTx(ctx, tx, convID, models.SupportSenderPlatform,
                                principal.ID, senderDisplayName(principal),
                                note["text"].(string), nil, true, note["kind"].(string))
                        if err != nil {
                                log.Printf("[support] ticket_update_failed: %v", err)
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_update_failed"})
                                return
                        }
                        messages = append(messages, msg)
                }
        }

        // Platform audit row — the who/when/what of every lifecycle change.
        metadata := gin.H{
                "ticket_number": fresh.Number,
                "fields":        systemNotes,
        }
        if body.ResolutionNote != nil {
                metadata["resolution_note_updated"] = true
        }
        if err := writePlatformAuditLog(ctx, tx, principal, "support.ticket.update", "support",
                "support_ticket", fresh.ID, fresh.CompanyID, metadata,
                "Support ticket "+fresh.Number+" updated"); err != nil {
                log.Printf("[support] ticket_update_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_update_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                log.Printf("[support] ticket_update_failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "ticket_update_failed"})
                return
        }

        // Post-commit pushes: ticket snapshot + the system messages.
        if h.supportHub != nil {
                if payload := marshalSupportEnvelope(supportEnvelope{
                        Type: "ticket.updated", CompanyID: fresh.CompanyID, Ticket: mustJSON(&fresh),
                }); payload != nil {
                        h.supportHub.toBoth(fresh.CompanyID, payload)
                }
                if convID != "" {
                        for _, msg := range messages {
                                if payload := marshalSupportEnvelope(supportEnvelope{
                                        Type: "message.new", ConversationID: convID, CompanyID: fresh.CompanyID,
                                        Message: mustJSON(msg),
                                }); payload != nil {
                                        h.supportHub.toBoth(fresh.CompanyID, payload)
                                }
                        }
                }
        }
        resp := gin.H{"ticket": fresh}
        if len(messages) > 0 {
                resp["system_messages"] = messages
        }
        c.JSON(http.StatusOK, resp)
}
