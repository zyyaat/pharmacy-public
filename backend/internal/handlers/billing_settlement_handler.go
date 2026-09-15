// Payment settlement & reconciliation (Phase S1, migration 32).
//
// Three money questions, now three separate answers:
//
//   CONFIRMED — payments.confirmed_at + confirmation_source (webhook with a
//               verified signature | sync pull | manual entry). Written by
//               the activation paths through markPaymentConfirmedTx.
//   ACTIVATED — applySucceededPaymentTx (unchanged; still the single
//               subscription transition for every proving path).
//   SETTLED   — payment_settlements. XPay pays out in batches from a
//               schedule its ops team controls; there is NO payout API and
//               NO payout webhook (docs.xpay.app → Payouts and settlement),
//               so settlement-to-bank is recorded here as an OPERATOR-
//               VERIFIED fact: the super admin matches the payout batch in
//               the XPay dashboard and records reference + amounts + note.
//               Every mutation is a 'settlement' event in the ledger plus a
//               platform audit row — who, when, why.
//
// The resync action closes the lost-webhook gap: GET /checkout/sessions/:id
// asks XPay directly, and the same guards as the webhook decide whether the
// answer may activate anything (amount match, already-processed short
// circuit, succeeded never regresses — a session that stopped being paid
// while our row says succeeded is a conflict flagged for review, never an
// automatic rollback).
package handlers

import (
        "context"
        "encoding/json"
        "log"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
        "github.com/pharmacy-os/backend/internal/xpay"
)

// ensureSettlementRowTx creates the settlement snapshot for an ONLINE
// payment when missing (idempotent — activation paths may fire more than
// once across webhook + resync). Status starts 'pending': the provider
// captured the money; the bank payout is not verified yet.
func ensureSettlementRowTx(ctx context.Context, tx pgx.Tx, paymentID, provider, currency string, amount int64) error {
        _, err := tx.Exec(ctx, `
                INSERT INTO payment_settlements
                    (payment_id, provider, status, currency, settled_amount_piastres, last_synced_at)
                VALUES ($1, $2, $3, $4, $5, NOW())
                ON CONFLICT (payment_id) DO NOTHING
        `, paymentID, provider, models.SettlementStatusPending, currency, amount)
        return err
}

// markPaymentConfirmedTx stamps HOW a payment's success became known. The
// first confirmation wins (a webhook that landed before a resync keeps its
// earlier timestamp — re-confirmation never rewrites history).
func markPaymentConfirmedTx(ctx context.Context, tx pgx.Tx, paymentID, source string) error {
        _, err := tx.Exec(ctx, `
                UPDATE payments
                SET confirmed_at = COALESCE(confirmed_at, NOW()),
                    confirmation_source = COALESCE(confirmation_source, $2),
                    updated_at = NOW()
                WHERE id = $1
        `, paymentID, source)
        return err
}

// flagPaymentReviewTx raises the review flag with a reason (the pairing of
// payments.needs_review with settlement 'unknown'/'disputed').
func flagPaymentReviewTx(ctx context.Context, tx pgx.Tx, paymentID, reason string) error {
        _, err := tx.Exec(ctx, `
                UPDATE payments
                SET needs_review = TRUE, review_reason = $2, updated_at = NOW()
                WHERE id = $1
        `, paymentID, reason)
        return err
}

// setSettlementStatusTx moves the settlement snapshot to a new status
// (row created on the spot when an event outran activation bookkeeping).
func setSettlementStatusTx(ctx context.Context, tx pgx.Tx, paymentID, provider, currency, status string) error {
        _, err := tx.Exec(ctx, `
                INSERT INTO payment_settlements (payment_id, provider, status, currency)
                VALUES ($1, $2, $3, $4)
                ON CONFLICT (payment_id) DO UPDATE
                        SET status = EXCLUDED.status, updated_at = NOW()
        `, paymentID, provider, status, currency)
        return err
}

// ---------------------------------------------------------------------------
// POST /platform-admin/payments/:id/settlement — the operator records the
// financial truth after matching the payout batch in the XPay dashboard.
// Body: status (settled | partially_settled | failed | disputed | pending),
// settled_amount_piastres?, fees_piastres?, provider_settlement_reference?,
// settled_at?, note (REQUIRED — every manual money-state edit carries its
// why). Manual payments are rejected: there is no provider to settle with.
// ---------------------------------------------------------------------------
func (h *Handler) SettlePlatformPayment(c *gin.Context) {
        id := c.Param("id")
        var body struct {
                Status                      string     `json:"status"`
                SettledAmountPiastres       *int64     `json:"settled_amount_piastres"`
                FeesPiastres                *int64     `json:"fees_piastres"`
                ProviderSettlementReference string     `json:"provider_settlement_reference"`
                SettledAt                   *time.Time `json:"settled_at"`
                Note                        string     `json:"note"`
        }
        if err := c.ShouldBindJSON(&body); err != nil || body.Status == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body",
                        "message": "status مطلوب (settled | partially_settled | failed | disputed | pending)"})
                return
        }
        note := strings.TrimSpace(body.Note)
        if note == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "note_required",
                        "message": "سبب التعديل مطلوب — كل تغيير مالي يدوي يُسجَّل بمن قام به ولماذا"})
                return
        }
        switch body.Status {
        case models.SettlementStatusSettled, models.SettlementStatusPartiallySettled,
                models.SettlementStatusFailed, models.SettlementStatusDisputed,
                models.SettlementStatusPending:
        default:
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status",
                        "message": "حالة تسوية غير معروفة"})
                return
        }
        reference := strings.TrimSpace(body.ProviderSettlementReference)
        if reference == "" && (body.Status == models.SettlementStatusSettled || body.Status == models.SettlementStatusPartiallySettled) {
                c.JSON(http.StatusBadRequest, gin.H{"error": "reference_required",
                        "message": "مرجع دفعة التحويل (payout batch) من لوحة XPay مطلوب لتوثيق التسوية"})
                return
        }

        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.ID == "" {
                c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication_required"})
                return
        }
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var paymentStatus, provider, currency, companyID string
        var amount int64
        err = tx.QueryRow(ctx, `
                SELECT status, provider, currency, company_id::text, amount_piastres
                FROM payments WHERE id = $1 FOR UPDATE
        `, id).Scan(&paymentStatus, &provider, &currency, &companyID, &amount)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusNotFound, gin.H{"error": "payment_not_found"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_lookup_failed"})
                return
        }
        if provider == "manual" {
                c.JSON(http.StatusConflict, gin.H{"error": "manual_payment_has_no_settlement",
                        "message": "الدفعات اليدوية لا تسوية مع مزود — لا صف تسوية لها"})
                return
        }
        if paymentStatus != models.PaymentStatusSucceeded {
                c.JSON(http.StatusConflict, gin.H{"error": "payment_not_settleable",
                        "message": "التسوية تُسجَّل على الدفعات المؤكدة فقط — حالة هذه الدفعة " + paymentStatus})
                return
        }

        settledAt := time.Now()
        if body.SettledAt != nil {
                settledAt = *body.SettledAt
        }
        settledAmount := amount
        if body.SettledAmountPiastres != nil {
                settledAmount = *body.SettledAmountPiastres
        }
        if _, err := tx.Exec(ctx, `
                INSERT INTO payment_settlements
                    (payment_id, provider, status, settled_amount_piastres, fees_piastres,
                     currency, provider_settlement_reference, settled_at, last_synced_at)
                VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), $8, NOW())
                ON CONFLICT (payment_id) DO UPDATE SET
                    status = EXCLUDED.status,
                    settled_amount_piastres = EXCLUDED.settled_amount_piastres,
                    fees_piastres = EXCLUDED.fees_piastres,
                    provider_settlement_reference = EXCLUDED.provider_settlement_reference,
                    settled_at = EXCLUDED.settled_at,
                    last_synced_at = NOW(),
                    updated_at = NOW()
        `, id, provider, body.Status, settledAmount, body.FeesPiastres,
                currency, reference, settledAt); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "settlement_update_failed", "detail": err.Error()})
                return
        }

        // Resolving a conflict clears the flag; opening one raises it.
        reviewCleared := false
        if body.Status == models.SettlementStatusSettled || body.Status == models.SettlementStatusPartiallySettled {
                if _, err := tx.Exec(ctx, `
                        UPDATE payments SET needs_review = FALSE, review_reason = NULL, updated_at = NOW()
                        WHERE id = $1
                `, id); err == nil {
                        reviewCleared = true
                }
        }
        if body.Status == models.SettlementStatusDisputed || body.Status == models.SettlementStatusUnknown {
                if err := flagPaymentReviewTx(ctx, tx, id, note); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "review_flag_failed"})
                        return
                }
        }

        if _, err := tx.Exec(ctx, `
                INSERT INTO payment_transactions (payment_id, txn_type, amount_piastres, hmac_verified, payload)
                VALUES ($1, 'settlement', $2, FALSE, jsonb_build_object(
                        'from_status', 'pending', 'to_status', $3::text,
                        'settled_amount_piastres', $4::bigint, 'fees_piastres', $5::bigint,
                        'reference', NULLIF($6, '')::text, 'note', $7::text,
                        'actor', $8::text, 'review_cleared', $9::boolean))
        `, id, amount, body.Status, settledAmount, body.FeesPiastres,
                reference, note, principal.Email, reviewCleared); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "settlement_txn_failed", "detail": err.Error()})
                return
        }

        if err := writePlatformAuditLog(ctx, tx, principal, "payment.settlement", "billing",
                "payment", id, companyID,
                map[string]any{"company_id": companyID, "settlement_status": body.Status,
                        "settled_amount_piastres": settledAmount, "fees_piastres": body.FeesPiastres,
                        "reference": reference},
                "تسجيل تسوية دفعة "+note); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "settlement_audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "settlement_commit_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "payment_id":        id,
                "settlement_status": body.Status,
                "settled_at":        settledAt.UTC().Format(time.RFC3339),
                "review_cleared":    reviewCleared,
        }})
}

// ---------------------------------------------------------------------------
// POST /platform-admin/payments/:id/resync — pull the session from XPay and
// let the answer drive the SAME guarded transitions the webhook uses. The
// one activation path stays applySucceededPaymentTx; nothing here trusts the
// client, only the provider API over our server-only secret key.
// ---------------------------------------------------------------------------
func (h *Handler) ResyncPlatformPayment(c *gin.Context) {
        id := c.Param("id")
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.ID == "" {
                c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication_required"})
                return
        }
        if h.config == nil || h.config.XPAYSecretKey == "" {
                c.JSON(http.StatusServiceUnavailable, gin.H{"error": "xpay_not_configured",
                        "message": "المزامنة مع XPay غير مهيأة على هذا الخادم"})
                return
        }
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var paymentStatus, provider, currency, companyID, planID, sessionRef string
        var amount int64
        err = tx.QueryRow(ctx, `
                SELECT status, provider, currency, company_id::text, plan_id::text,
                       COALESCE(provider_reference, ''), amount_piastres
                FROM payments WHERE id = $1 FOR UPDATE
        `, id).Scan(&paymentStatus, &provider, &currency, &companyID, &planID, &sessionRef, &amount)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusNotFound, gin.H{"error": "payment_not_found"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_lookup_failed"})
                return
        }
        if provider != "xpay" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "resync_not_supported_provider",
                        "message": "المزامنة السحبية متاحة لدفعات XPay فقط حاليًا"})
                return
        }
        if sessionRef == "" {
                c.JSON(http.StatusConflict, gin.H{"error": "session_reference_missing",
                        "message": "لا يوجد معرف جلسة مخزّن لهذه الدفعة — أنشئ جلسة دفع أولًا"})
                return
        }

        client := xpay.New(h.config.XPAYSecretKey, h.config.XPAYPublishableKey, h.config.XPAYBaseURL)
        session, err := client.RetrieveCheckoutSession(ctx, sessionRef)
        if err != nil {
                // The failure itself is ledger-worthy: the operator sees WHEN the
                // provider was unreachable and what it said.
                _, _ = tx.Exec(ctx, `
                        INSERT INTO payment_transactions (payment_id, txn_type, hmac_verified, payload)
                        VALUES ($1, 'sync', FALSE, jsonb_build_object('error', $2::text, 'actor', $3::text))
                `, id, err.Error(), principal.Email)
                _ = tx.Commit(ctx)
                log.Printf("[settlement] resync provider call failed payment=%s: %v", id, err)
                c.JSON(http.StatusBadGateway, gin.H{"error": "xpay_retrieve_failed",
                        "message": "تعذر جلب حالة الجلسة من XPay — حاول مرة أخرى"})
                return
        }

        recordSync := func(result string, extra map[string]any) {
                payload := map[string]any{
                        "actor": principal.Email, "result": result,
                        "session_id": session.ID, "session_status": session.Status,
                        "payment_status": session.PaymentStatus, "amount_total": session.AmountTotal,
                }
                for k, v := range extra {
                        payload[k] = v
                }
                _, _ = tx.Exec(ctx, `
                        INSERT INTO payment_transactions (payment_id, txn_type, provider_transaction_id,
                                                          amount_piastres, hmac_verified, payload)
                        VALUES ($1, 'sync', NULLIF($2, ''), $3, FALSE, $4::jsonb)
                `, id, session.ID, session.AmountTotal, rawJSON(payload))
        }

        switch {
        case paymentStatus == models.PaymentStatusPending && session.PaymentStatus == "paid":
                if session.AmountTotal != amount {
                        // The provider's own API disagrees with our snapshot — the
                        // webhook's amount-tamper rule, now on the pull path: never
                        // activate on a mismatch, flag for review.
                        recordSync("amount_mismatch_flagged", nil)
                        if err := flagPaymentReviewTx(ctx, tx, id,
                                "amount mismatch on resync: provider says "+formatInt64(session.AmountTotal)+
                                        ", stored "+formatInt64(amount)); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "review_flag_failed"})
                                return
                        }
                        if err := setSettlementStatusTx(ctx, tx, id, provider, currency, models.SettlementStatusUnknown); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "settlement_update_failed"})
                                return
                        }
                        if err := writePlatformAuditLog(ctx, tx, principal, "payment.resync", "billing",
                                "payment", id, companyID,
                                map[string]any{"result": "amount_mismatch", "provider_amount": session.AmountTotal,
                                        "stored_amount": amount},
                                "مزامنة دفعة: اختلاف مبلغ مع المزود — رُفعت للمراجعة"); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "resync_audit_failed"})
                                return
                        }
                        _ = tx.Commit(ctx)
                        c.JSON(http.StatusOK, gin.H{"data": gin.H{"payment_id": id, "result": "conflict_flagged",
                                "provider": gin.H{"paymentStatus": session.PaymentStatus, "amountTotal": session.AmountTotal}}})
                        return
                }
                // The lost-webhook recovery: confirm through the SAME transition
                // the webhook uses, stamped confirmation_source='sync'.
                if _, err := applySucceededPaymentTx(ctx, tx, companyID, planID,
                        paymentBillingInterval(ctx, tx, id), id); err != nil {
                        log.Printf("[settlement] resync activation failed payment=%s: %v", id, err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "activation_failed"})
                        return
                }
                if _, err := tx.Exec(ctx, `
                        UPDATE payments SET status = 'succeeded', failure_code = NULL,
                                            failure_message = NULL, updated_at = NOW()
                        WHERE id = $1
                `, id); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_update_failed"})
                        return
                }
                if err := markPaymentConfirmedTx(ctx, tx, id, models.PaymentConfirmedBySync); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "confirmation_stamp_failed"})
                        return
                }
                if err := ensureSettlementRowTx(ctx, tx, id, provider, currency, amount); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "settlement_row_failed"})
                        return
                }
                recordSync("activated", nil)
                if err := writePlatformAuditLog(ctx, tx, principal, "payment.resync", "billing",
                        "payment", id, companyID,
                        map[string]any{"result": "activated", "session_id": session.ID},
                        "مزامنة دفعة: أكدها المزود عبر السحب — فُعّل الاشتراك"); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "resync_audit_failed"})
                        return
                }
                if err := tx.Commit(ctx); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "resync_commit_failed"})
                        return
                }
                h.subs.Invalidate(companyID)
                c.JSON(http.StatusOK, gin.H{"data": gin.H{"payment_id": id, "result": "activated",
                        "provider": gin.H{"paymentStatus": session.PaymentStatus, "amountTotal": session.AmountTotal}}})

        case paymentStatus == models.PaymentStatusPending && session.Status == "expired":
                recordSync("failed_marked", nil)
                if _, err := tx.Exec(ctx, `
                        UPDATE payments SET status = 'failed', failure_code = 'session_expired',
                                            failure_message = 'XPay session expired (confirmed by resync)',
                                            updated_at = NOW()
                        WHERE id = $1
                `, id); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_update_failed"})
                        return
                }
                if err := writePlatformAuditLog(ctx, tx, principal, "payment.resync", "billing",
                        "payment", id, companyID,
                        map[string]any{"result": "expired"},
                        "مزامنة دفعة: الجلسة منتهية لدى المزود — فُشلت الدفعة"); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "resync_audit_failed"})
                        return
                }
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"data": gin.H{"payment_id": id, "result": "failed_marked"}})

        case paymentStatus == models.PaymentStatusSucceeded && session.PaymentStatus == "paid":
                // Both sides agree — just refresh the sync clock.
                recordSync("consistent", nil)
                if _, err := tx.Exec(ctx, `
                        UPDATE payment_settlements SET last_synced_at = NOW(), updated_at = NOW()
                        WHERE payment_id = $1
                `, id); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "settlement_update_failed"})
                        return
                }
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"data": gin.H{"payment_id": id, "result": "consistent"}})

        case paymentStatus == models.PaymentStatusSucceeded:
                // We say succeeded, the provider no longer does. Never regress a
                // succeeded payment — flag for human review instead.
                recordSync("succeeded_conflict_flagged", nil)
                if err := flagPaymentReviewTx(ctx, tx, id,
                        "resync: payment is succeeded locally but provider reports paymentStatus="+
                                session.PaymentStatus+"/status="+session.Status); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "review_flag_failed"})
                        return
                }
                if err := setSettlementStatusTx(ctx, tx, id, provider, currency, models.SettlementStatusUnknown); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "settlement_update_failed"})
                        return
                }
                if err := writePlatformAuditLog(ctx, tx, principal, "payment.resync", "billing",
                        "payment", id, companyID,
                        map[string]any{"result": "succeeded_conflict", "provider_payment_status": session.PaymentStatus},
                        "مزامنة دفعة: تعارض حالة النجاح مع المزود — رُفعت للمراجعة"); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "resync_audit_failed"})
                        return
                }
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"data": gin.H{"payment_id": id, "result": "conflict_flagged"}})

        default:
                // pending & still open (or any combination without a rule): no
                // state change, the sync clock and the ledger row still move.
                recordSync("no_change", nil)
                if err := ensureSettlementRowTx(ctx, tx, id, provider, currency, amount); err == nil {
                        _, _ = tx.Exec(ctx, `
                                UPDATE payment_settlements SET last_synced_at = NOW(), updated_at = NOW()
                                WHERE payment_id = $1
                        `, id)
                }
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"data": gin.H{"payment_id": id, "result": "no_change",
                        "provider": gin.H{"status": session.Status, "paymentStatus": session.PaymentStatus}}})
        }
}

// reconciliationRow is the shared shape of every bucket entry.
type reconciliationRow struct {
        ID              string     `json:"id"`
        Number          string     `json:"number"`
        CompanyID       string     `json:"company_id"`
        CompanyName     string     `json:"company_name"`
        CompanyEmail    string     `json:"company_email"`
        PlanSlug        string     `json:"plan_slug"`
        PlanName        string     `json:"plan_name"`
        AmountPiastres  int64      `json:"amount_piastres"`
        Currency        string     `json:"currency"`
        Provider        string     `json:"provider"`
        Status          string     `json:"status"`
        SettlementStatus string    `json:"settlement_status"`
        ProviderRef     string     `json:"provider_reference"`
        NeedsReview     bool       `json:"needs_review"`
        ReviewReason    string     `json:"review_reason,omitempty"`
        CreatedAt       time.Time  `json:"created_at"`
        ConfirmedAt     *time.Time `json:"confirmed_at,omitempty"`
}

const reconciliationSelect = `
        SELECT p.id::text, COALESCE(p.number, ''), p.company_id::text, c.name, COALESCE(c.email, ''),
               pl.slug, pl.name, p.amount_piastres, p.currency, p.provider, p.status,
               COALESCE(ps.status, CASE WHEN p.provider = 'manual' THEN 'manual' ELSE 'missing' END),
               COALESCE(p.provider_reference, ''), p.needs_review, COALESCE(p.review_reason, ''),
               p.created_at, p.confirmed_at
        FROM payments p
        JOIN companies c ON c.id = p.company_id
        JOIN plans pl ON pl.id = p.plan_id
        LEFT JOIN payment_settlements ps ON ps.payment_id = p.id
`

func scanReconciliationRows(rows pgx.Rows) []reconciliationRow {
        out := make([]reconciliationRow, 0)
        defer rows.Close()
        for rows.Next() {
                var r reconciliationRow
                if err := rows.Scan(&r.ID, &r.Number, &r.CompanyID, &r.CompanyName, &r.CompanyEmail,
                        &r.PlanSlug, &r.PlanName, &r.AmountPiastres, &r.Currency, &r.Provider,
                        &r.Status, &r.SettlementStatus, &r.ProviderRef, &r.NeedsReview,
                        &r.ReviewReason, &r.CreatedAt, &r.ConfirmedAt); err == nil {
                        out = append(out, r)
                }
        }
        return out
}

// ---------------------------------------------------------------------------
// GET /platform-admin/payments/reconciliation — the operator's matching
// worklist. Buckets stay read-only; the actions live on the payment (settle,
// resync) so every state change keeps its single audited entry point.
// ---------------------------------------------------------------------------
func (h *Handler) PaymentsReconciliation(c *gin.Context) {
        ctx := c.Request.Context()
        staleCutoff := time.Now().Add(-time.Duration(models.StalePendingHours) * time.Hour)

        // Summary counters over the whole ledger (not just the capped lists).
        var staleCount, unsettledCount, reviewCount, conflictCount, refundedCount int
        var confirmedUnsettledPiastres int64
        if err := h.db.QueryRow(ctx, `
                SELECT
                    COUNT(*) FILTER (WHERE p.provider <> 'manual' AND p.status = 'pending'
                                       AND p.created_at < $1),
                    COUNT(*) FILTER (WHERE p.provider <> 'manual' AND p.status = 'succeeded'
                                       AND COALESCE(ps.status, 'missing') NOT IN ('settled','partially_settled')),
                    COUNT(*) FILTER (WHERE p.needs_review),
                    COUNT(*) FILTER (WHERE ps.status IN ('unknown','disputed','failed')),
                    COUNT(*) FILTER (WHERE p.status = 'refunded' OR p.refunded_amount_piastres > 0),
                    COALESCE(SUM(p.amount_piastres) FILTER (WHERE p.provider <> 'manual'
                                       AND p.status = 'succeeded'
                                       AND COALESCE(ps.status, 'missing') NOT IN ('settled','partially_settled')), 0)::bigint
                FROM payments p
                LEFT JOIN payment_settlements ps ON ps.payment_id = p.id
        `, staleCutoff).Scan(&staleCount, &unsettledCount, &reviewCount,
                &conflictCount, &refundedCount, &confirmedUnsettledPiastres); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reconciliation_summary_failed"})
                return
        }

        load := func(where string, args ...any) []reconciliationRow {
                rows, err := h.db.Query(ctx, reconciliationSelect+where, args...)
                if err != nil {
                        log.Printf("[settlement] reconciliation bucket query failed: %v", err)
                        return []reconciliationRow{}
                }
                return scanReconciliationRows(rows)
        }

        // 1 — pending online payments old enough to be suspicious: the session
        // was abandoned (resync will fail them) or the webhook was lost
        // (resync will activate). The worklist's headline bucket.
        stale := load(`WHERE p.provider <> 'manual' AND p.status = 'pending' AND p.created_at < $1
                       ORDER BY p.created_at ASC LIMIT 50`, staleCutoff)

        // 2 — confirmed by the provider but never matched to a payout batch:
        // money in XPay's balance, not yet proven in our bank.
        unsettled := load(`WHERE p.provider <> 'manual' AND p.status = 'succeeded'
                             AND COALESCE(ps.status, 'missing') NOT IN ('settled','partially_settled')
                             ORDER BY p.confirmed_at NULLS LAST, p.created_at ASC LIMIT 50`)

        // 3 — the review queue: amount conflicts, succeeded-vs-provider
        // contradictions, anything the machine refused to decide.
        review := load(`WHERE p.needs_review ORDER BY p.updated_at DESC LIMIT 50`)

        // 4 — settlement snapshots in a bad state (unknown/disputed/failed).
        conflicts := load(`WHERE ps.status IN ('unknown','disputed','failed')
                             ORDER BY ps.updated_at DESC LIMIT 50`)

        // 5 — money that came back: full or partial refunds, for the payout
        // batch matching on the refund side.
        refunded := load(`WHERE p.status = 'refunded' OR p.refunded_amount_piastres > 0
                            ORDER BY p.updated_at DESC LIMIT 50`)

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "summary": gin.H{
                        "stale_pending_count":            staleCount,
                        "confirmed_unsettled_count":      unsettledCount,
                        "confirmed_unsettled_piastres":   confirmedUnsettledPiastres,
                        "needs_review_count":             reviewCount,
                        "settlement_conflicts_count":     conflictCount,
                        "refunded_count":                 refundedCount,
                        "stale_pending_after_hours":      models.StalePendingHours,
                },
                "stale_pending":        stale,
                "confirmed_unsettled":  unsettled,
                "needs_review":         review,
                "settlement_conflicts": conflicts,
                "refunded":             refunded,
        }})
}

// ---------------------------------------------------------------------------
// GET /platform-admin/payments/:id — the payment detail surface: the ledger
// row (with its settlement snapshot) plus the append-only event timeline
// (intents, verified webhooks, syncs, settlements, reviews, refunds) so the
// operator can answer "what exactly happened to this money" from one place.
// ---------------------------------------------------------------------------
func (h *Handler) GetPlatformPaymentDetail(c *gin.Context) {
        id := c.Param("id")
        ctx := c.Request.Context()

        var row reconciliationRow
        var failureCode, failureMessage, confirmationSource string
        var refundedAmount int64
        var settledAt, lastSyncedAt *time.Time
        var settledAmount, fees *int64
        var settlementRef string
        err := h.db.QueryRow(ctx, `
                SELECT p.id::text, COALESCE(p.number, ''), p.company_id::text, c.name, COALESCE(c.email, ''),
                       pl.slug, pl.name, p.amount_piastres, p.currency, p.provider, p.status,
                       COALESCE(ps.status, CASE WHEN p.provider = 'manual' THEN 'manual' ELSE 'missing' END),
                       COALESCE(p.provider_reference, ''), p.needs_review, COALESCE(p.review_reason, ''),
                       p.created_at, p.confirmed_at,
                       COALESCE(p.confirmation_source, ''), COALESCE(p.failure_code, ''),
                       COALESCE(p.failure_message, ''), p.refunded_amount_piastres,
                       ps.settled_amount_piastres, ps.fees_piastres,
                       COALESCE(ps.provider_settlement_reference, ''), ps.settled_at, ps.last_synced_at
                FROM payments p
                JOIN companies c ON c.id = p.company_id
                JOIN plans pl ON pl.id = p.plan_id
                LEFT JOIN payment_settlements ps ON ps.payment_id = p.id
                WHERE p.id = $1
        `, id).Scan(&row.ID, &row.Number, &row.CompanyID, &row.CompanyName, &row.CompanyEmail,
                &row.PlanSlug, &row.PlanName, &row.AmountPiastres, &row.Currency, &row.Provider,
                &row.Status, &row.SettlementStatus, &row.ProviderRef, &row.NeedsReview,
                &row.ReviewReason, &row.CreatedAt, &row.ConfirmedAt,
                &confirmationSource, &failureCode, &failureMessage, &refundedAmount,
                &settledAmount, &fees, &settlementRef, &settledAt, &lastSyncedAt)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusNotFound, gin.H{"error": "payment_not_found"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_detail_failed"})
                return
        }

        rows, err := h.db.Query(ctx, `
                SELECT txn_type, COALESCE(provider_transaction_id, ''), COALESCE(amount_piastres, 0),
                       hmac_verified, COALESCE(payload::text, '{}'), created_at
                FROM payment_transactions WHERE payment_id = $1
                ORDER BY created_at ASC, id ASC LIMIT 200
        `, id)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_timeline_failed"})
                return
        }
        defer rows.Close()
        timeline := make([]gin.H, 0)
        for rows.Next() {
                var txnType, providerTxnID, payload string
                var amount int64
                var verified bool
                var createdAt time.Time
                if err := rows.Scan(&txnType, &providerTxnID, &amount, &verified, &payload, &createdAt); err == nil {
                        timeline = append(timeline, gin.H{
                                "txn_type":                txnType,
                                "provider_transaction_id": providerTxnID,
                                "amount_piastres":         amount,
                                "hmac_verified":           verified,
                                "payload":                 json.RawMessage(payload),
                                "created_at":              createdAt.UTC().Format(time.RFC3339),
                        })
                }
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "id":                       row.ID,
                "number":                   row.Number,
                "company":                  gin.H{"id": row.CompanyID, "name": row.CompanyName, "email": row.CompanyEmail},
                "plan":                     gin.H{"slug": row.PlanSlug, "name": row.PlanName},
                "amount_piastres":          row.AmountPiastres,
                "currency":                 row.Currency,
                "provider":                 row.Provider,
                "status":                   row.Status,
                "provider_reference":       row.ProviderRef,
                "needs_review":             row.NeedsReview,
                "review_reason":            row.ReviewReason,
                "created_at":               row.CreatedAt.UTC().Format(time.RFC3339),
                "confirmed_at":             formatRFC3339Nullable(row.ConfirmedAt),
                "confirmation_source":      confirmationSource,
                "failure_code":             failureCode,
                "failure_message":          failureMessage,
                "refunded_amount_piastres": refundedAmount,
                "settlement": gin.H{
                        "status":           row.SettlementStatus,
                        "settled_amount":   settledAmount,
                        "fees_piastres":    fees,
                        "reference":        settlementRef,
                        "settled_at":       formatRFC3339Nullable(settledAt),
                        "last_synced_at":   formatRFC3339Nullable(lastSyncedAt),
                },
                "timeline": timeline,
        }})
}
