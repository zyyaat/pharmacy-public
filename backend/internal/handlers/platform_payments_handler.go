// Platform-admin payments ledger + billing overview + refunds
// (Task 90 — subscriptions best-practice pass).
//
// Global best practice alignment (Stripe Billing / 2026 SaaS norms):
//
//   - A payments LEDGER: every manual or Paymob payment is browsable with
//     filters — the operator can finally SEE the money, not just register it.
//   - A billing OVERVIEW: counts by status, monthly-recurring estimate
//     (monthly price for monthly interval, yearly/12 for yearly),
//     subscriptions expiring within 7 days (pre-dunning list) and the last
//     30 days' collected revenue.
//   - REFUNDS as first-class ledger events: a succeeded payment can be
//     refunded once; the refund is recorded in payment_transactions, the
//     audit log, and — when the operator opts in — the linked live
//     subscription period is shortened by the payment's billing interval
//     (Stripe's "refund shortens the service window" semantics).
package handlers

import (
        "net/http"
        "strconv"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
)

// ListPlatformPayments returns the payments ledger (manual + online) with
// company and plan labels. Filters: status, provider, company_id, search,
// needs_review, settlement (settlement-state filter). Phase S1 exposes the
// reconciliation columns inline: number, confirmation, settlement state,
// review flag, refund amount.
func (h *Handler) ListPlatformPayments(c *gin.Context) {
        ctx := c.Request.Context()
        page, pageSize := pagination(c)
        status := strings.TrimSpace(c.Query("status"))
        provider := strings.TrimSpace(c.Query("provider"))
        companyID := strings.TrimSpace(c.Query("company_id"))
        search := strings.TrimSpace(c.Query("search"))
        needsReview := strings.TrimSpace(c.Query("needs_review"))
        settlement := strings.TrimSpace(c.Query("settlement"))

        where := []string{"TRUE"}
        args := make([]any, 0, 7)
        if status != "" {
                args = append(args, status)
                where = append(where, "p.status = $"+strconv.Itoa(len(args)))
        }
        if provider != "" {
                args = append(args, provider)
                where = append(where, "p.provider = $"+strconv.Itoa(len(args)))
        }
        if companyID != "" {
                args = append(args, companyID)
                where = append(where, "p.company_id::text = $"+strconv.Itoa(len(args)))
        }
        if search != "" {
                args = append(args, "%"+search+"%")
                where = append(where, "(c.name ILIKE $"+strconv.Itoa(len(args))+" OR c.email ILIKE $"+strconv.Itoa(len(args))+")")
        }
        if needsReview == "true" || needsReview == "1" {
                where = append(where, "p.needs_review")
        }
        if settlement == "unsettled" {
                where = append(where, "p.provider <> 'manual' AND COALESCE(ps.status, 'missing') NOT IN ('settled','partially_settled')")
        } else if settlement != "" {
                args = append(args, settlement)
                where = append(where, "ps.status = $"+strconv.Itoa(len(args)))
        }
        whereSQL := strings.Join(where, " AND ")

        var total int
        if err := h.db.QueryRow(ctx, `
                SELECT COUNT(*)::int
                FROM payments p
                JOIN companies c ON c.id = p.company_id
                LEFT JOIN payment_settlements ps ON ps.payment_id = p.id
                WHERE `+whereSQL, args...).Scan(&total); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payments_count_failed"})
                return
        }

        args = append(args, pageSize, (page-1)*pageSize)
        limitIdx := strconv.Itoa(len(args) - 1)
        offsetIdx := strconv.Itoa(len(args))
        rows, err := h.db.Query(ctx, `
                SELECT p.id::text, COALESCE(p.number, ''), p.company_id::text, c.name, c.email,
                       p.plan_id::text, pl.slug, pl.name, COALESCE(pl.name_ar, ''),
                       p.billing_interval, p.amount_piastres, p.currency,
                       p.provider, p.status,
                       COALESCE(p.metadata->>'note', ''),
                       COALESCE(p.subscription_id::text, ''), p.created_at,
                       p.confirmed_at, COALESCE(p.confirmation_source, ''),
                       COALESCE(p.failure_code, ''), COALESCE(p.failure_message, ''),
                       p.refunded_amount_piastres, p.needs_review, COALESCE(p.review_reason, ''),
                       COALESCE(ps.status, CASE WHEN p.provider = 'manual' THEN 'manual' ELSE 'missing' END),
                       COALESCE(ps.provider_settlement_reference, ''), ps.settled_at
                FROM payments p
                JOIN companies c ON c.id = p.company_id
                JOIN plans pl ON pl.id = p.plan_id
                LEFT JOIN payment_settlements ps ON ps.payment_id = p.id
                WHERE `+whereSQL+`
                ORDER BY p.created_at DESC
                LIMIT $`+limitIdx+` OFFSET $`+offsetIdx, args...)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payments_query_failed"})
                return
        }
        defer rows.Close()

        payments := make([]gin.H, 0)
        for rows.Next() {
                var id, companyIDStr, companyName, companyEmail, planID, planSlug, planName, planNameAr string
                var interval, currency, provider, status, note, subscriptionID string
                var number, confirmationSource, failureCode, failureMessage, reviewReason, settlementStatus, settlementRef string
                var amount, refundedAmount int64
                var createdAt time.Time
                var confirmedAt, settledAt *time.Time
                var needsReview bool
                if err := rows.Scan(&id, &number, &companyIDStr, &companyName, &companyEmail,
                        &planID, &planSlug, &planName, &planNameAr,
                        &interval, &amount, &currency, &provider, &status,
                        &note, &subscriptionID, &createdAt,
                        &confirmedAt, &confirmationSource,
                        &failureCode, &failureMessage,
                        &refundedAmount, &needsReview, &reviewReason,
                        &settlementStatus, &settlementRef, &settledAt); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "payments_scan_failed", "detail": err.Error()})
                        return
                }
                payments = append(payments, gin.H{
                        "id":               id,
                        "number":           number,
                        "company":          gin.H{"id": companyIDStr, "name": companyName, "email": companyEmail},
                        "plan":             gin.H{"id": planID, "slug": planSlug, "name": planName, "name_ar": planNameAr},
                        "billing_interval": interval,
                        "amount_piastres":  amount,
                        "currency":         currency,
                        "provider":         provider,
                        "status":           status,
                        "note":             note,
                        "subscription_id":  subscriptionID,
                        "created_at":       createdAt.UTC().Format(time.RFC3339),
                        // Phase S1 reconciliation surface
                        "confirmed_at":         formatRFC3339Nullable(confirmedAt),
                        "confirmation_source":  confirmationSource,
                        "failure_code":         failureCode,
                        "failure_message":      failureMessage,
                        "refunded_amount_piastres": refundedAmount,
                        "needs_review":         needsReview,
                        "review_reason":        reviewReason,
                        "settlement_status":    settlementStatus,
                        "settlement_reference": settlementRef,
                        "settled_at":           formatRFC3339Nullable(settledAt),
                })
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payments_iterate_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{
                "data":       payments,
                "pagination": gin.H{"total": total, "page": page, "page_size": pageSize},
        })
}

// formatRFC3339Nullable renders an optional timestamp in the API's UTC
// RFC3339 convention (nil → empty string — the ledger's null-safe shape).
func formatRFC3339Nullable(t *time.Time) string {
        if t == nil {
                return ""
        }
        return t.UTC().Format(time.RFC3339)
}

// SubscriptionsOverview returns the operator KPIs for the subscriptions
// surface: live-state counts, MRR estimate, pending-cancellation count,
// the expiring-within-7-days watch list (pre-dunning) and the last 30
// days' collected revenue.
func (h *Handler) SubscriptionsOverview(c *gin.Context) {
        ctx := c.Request.Context()

        var activeCount, trialCount, terminalCount, cancellingCount int
        var mrrPiastres int64
        if err := h.db.QueryRow(ctx, `
                SELECT
                        COUNT(*) FILTER (WHERE s.status = 'active')::int,
                        COUNT(*) FILTER (WHERE s.status = 'trial')::int,
                        COUNT(*) FILTER (WHERE s.status IN ('expired','cancelled','suspended'))::int,
                        COUNT(*) FILTER (WHERE s.status = 'active' AND s.cancel_at_period_end)::int,
                        COALESCE(SUM(
                                CASE s.billing_interval
                                        WHEN 'yearly' THEN p.yearly_price_piastres / 12
                                        ELSE p.monthly_price_piastres
                                END
                        ), 0)::bigint
                FROM subscriptions s
                JOIN plans p ON p.id = s.plan_id
                WHERE s.status IN ('trial','active')
        `).Scan(&activeCount, &trialCount, &terminalCount, &cancellingCount, &mrrPiastres); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "overview_query_failed"})
                return
        }

        var payments30Count int
        var payments30Piastres int64
        if err := h.db.QueryRow(ctx, `
                SELECT COUNT(*)::int, COALESCE(SUM(amount_piastres), 0)::bigint
                FROM payments
                WHERE status = 'succeeded' AND created_at >= NOW() - INTERVAL '30 days'
        `).Scan(&payments30Count, &payments30Piastres); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "overview_payments_failed"})
                return
        }

        // Pre-dunning watch list: paid periods and trials ending within 7 days.
        rows, err := h.db.Query(ctx, `
                SELECT s.id::text, s.company_id::text, c.name, c.email,
                       p.name, COALESCE(p.name_ar, ''), s.status,
                       COALESCE(s.current_period_end, s.trial_ends_at), s.cancel_at_period_end
                FROM subscriptions s
                JOIN companies c ON c.id = s.company_id
                JOIN plans p ON p.id = s.plan_id
                WHERE s.status IN ('active','trial')
                  AND COALESCE(s.current_period_end, s.trial_ends_at) IS NOT NULL
                  AND COALESCE(s.current_period_end, s.trial_ends_at) <= NOW() + INTERVAL '7 days'
                ORDER BY COALESCE(s.current_period_end, s.trial_ends_at) ASC
                LIMIT 8
        `)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "overview_expiring_failed"})
                return
        }
        defer rows.Close()

        type expiringItem struct {
                ID                string     `json:"id"`
                CompanyID         string     `json:"company_id"`
                CompanyName       string     `json:"company_name"`
                CompanyEmail      string     `json:"company_email"`
                PlanName          string     `json:"plan_name"`
                PlanNameAr        string     `json:"plan_name_ar"`
                Status            string     `json:"status"`
                EndsAt            *time.Time `json:"ends_at"`
                CancelAtPeriodEnd bool       `json:"cancel_at_period_end"`
        }
        expiring := make([]expiringItem, 0)
        for rows.Next() {
                var it expiringItem
                var status string
                if err := rows.Scan(&it.ID, &it.CompanyID, &it.CompanyName, &it.CompanyEmail,
                        &it.PlanName, &it.PlanNameAr, &status, &it.EndsAt, &it.CancelAtPeriodEnd); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "overview_expiring_scan_failed"})
                        return
                }
                it.Status = status
                expiring = append(expiring, it)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "overview_expiring_iterate_failed"})
                return
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "active_count":           activeCount,
                "trial_count":            trialCount,
                "terminal_count":         terminalCount,
                "cancelling_count":       cancellingCount,
                "mrr_piastres":           mrrPiastres,
                "payments_30d_count":     payments30Count,
                "payments_30d_piastres":  payments30Piastres,
                "expiring_within_7_days": expiring,
        }})
}

// RefundPlatformPayment marks a succeeded payment as refunded, records the
// refund in the immutable transaction ledger, and — when
// shorten_subscription is set — pulls the linked live subscription's period
// end back by the payment's billing interval (the service window the
// customer is no longer paying for). Refunding twice is rejected.
func (h *Handler) RefundPlatformPayment(c *gin.Context) {
        id := c.Param("id")
        var body struct {
                Note                string `json:"note"`
                ShortenSubscription bool   `json:"shorten_subscription"`
        }
        _ = c.ShouldBindJSON(&body) // body optional

        principal, _ := auth.PrincipalFromContext(c)
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var paymentStatus, companyID, subscriptionID string
        var amount int64
        var interval *string
        err = tx.QueryRow(ctx, `
                SELECT p.status, p.company_id::text, p.amount_piastres,
                       p.billing_interval, COALESCE(p.subscription_id::text, '')
                FROM payments p WHERE p.id = $1
                FOR UPDATE
        `, id).Scan(&paymentStatus, &companyID, &amount, &interval, &subscriptionID)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusNotFound, gin.H{"error": "payment_not_found"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_lookup_failed"})
                return
        }
        if paymentStatus != models.PaymentStatusSucceeded {
                c.JSON(http.StatusConflict, gin.H{
                        "error":   "payment_not_refundable",
                        "message": "يمكن استرداد الدفعات الناجحة فقط — هذه الدفعة بحالة " + paymentStatus,
                })
                return
        }

        if _, err := tx.Exec(ctx, `
                UPDATE payments SET status = 'refunded',
                        refunded_amount_piastres = amount_piastres,
                        metadata = COALESCE(metadata, '{}'::jsonb)
                                || jsonb_build_object('refund_note', NULLIF($2, '')::text,
                                                      'refund_actor', $3::text,
                                                      'refunded_at', NOW()),
                       updated_at = NOW()
                WHERE id = $1
        `, id, strings.TrimSpace(body.Note), principal.Email); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "refund_update_failed"})
                return
        }

        if _, err := tx.Exec(ctx, `
                INSERT INTO payment_transactions (payment_id, txn_type, amount_piastres, hmac_verified, payload)
                VALUES ($1, 'refund', $2, FALSE, jsonb_build_object(
                        'note', NULLIF($3, '')::text, 'actor', $4::text, 'at', NOW()))
        `, id, amount, strings.TrimSpace(body.Note), principal.Email); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "refund_txn_failed"})
                return
        }

        shortened := false
        if body.ShortenSubscription && subscriptionID != "" {
                // Pull the period end back by exactly the interval this payment
                // bought — never before NOW (the customer keeps what already
                // elapsed; the lazy expiry handles an end landing in the past).
                var planInterval string
                if err := tx.QueryRow(ctx, `
                        SELECT s.billing_interval FROM subscriptions s WHERE s.id = $1
                `, subscriptionID).Scan(&planInterval); err == nil && planInterval != models.BillingIntervalNone {
                        if _, err := tx.Exec(ctx, `
                                UPDATE subscriptions SET
                                        current_period_end = GREATEST(
                                                NOW(),
                                                COALESCE(current_period_end, NOW()) -
                                                        CASE $2 WHEN 'yearly' THEN INTERVAL '1 year' ELSE INTERVAL '1 month' END),
                                        updated_at = NOW()
                                WHERE id = $1 AND status IN ('active','trial')
                        `, subscriptionID, planInterval); err == nil {
                                shortened = true
                        }
                }
        }

        _ = writePlatformAuditLog(ctx, tx, principal, "payment.refund", "billing", "payment", id, companyID,
                map[string]any{"company_id": companyID, "amount_piastres": amount,
                        "shorten_subscription": body.ShortenSubscription, "shortened": shortened},
                "استرداد دفعة بمبلغ "+strconv.FormatInt(amount, 10))
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "refund_commit_failed"})
                return
        }
        h.subs.Invalidate(companyID)
        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "id":        id,
                "status":    "refunded",
                "shortened": shortened,
        }})
}
