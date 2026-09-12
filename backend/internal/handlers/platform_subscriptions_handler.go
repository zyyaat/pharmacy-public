// Platform-admin subscription management + manual payments (Task 90).
//
// The super admin is the commercial operator until Paymob lands:
//   - assign/replace a company's plan manually (grandfathers, corrections);
//   - extend / cancel / suspend / reactivate subscriptions;
//   - register a manual payment (bank transfer, cash, aggregator) which
//     activates or extends the subscription exactly like a future Paymob
//     webhook will — the subscription transition logic is shared so the
//     payment provider never changes the billing semantics.
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

// ListPlatformSubscriptions returns the subscription ledger with company
// and plan labels. Filters: status, company_id, search (company name).
func (h *Handler) ListPlatformSubscriptions(c *gin.Context) {
        ctx := c.Request.Context()
        page, pageSize := pagination(c)
        status := strings.TrimSpace(c.Query("status"))
        companyID := strings.TrimSpace(c.Query("company_id"))
        search := strings.TrimSpace(c.Query("search"))

        where := []string{"TRUE"}
        args := make([]any, 0, 4)
        if status != "" {
                args = append(args, status)
                where = append(where, "s.status = $"+strconv.Itoa(len(args)))
        }
        if companyID != "" {
                args = append(args, companyID)
                where = append(where, "s.company_id::text = $"+strconv.Itoa(len(args)))
        }
        if search != "" {
                args = append(args, "%"+search+"%")
                where = append(where, "(c.name ILIKE $"+strconv.Itoa(len(args))+" OR c.email ILIKE $"+strconv.Itoa(len(args))+")")
        }
        whereSQL := strings.Join(where, " AND ")

        var total int
        if err := h.db.QueryRow(ctx, `
                SELECT COUNT(*)::int
                FROM subscriptions s
                JOIN companies c ON c.id = s.company_id
                WHERE `+whereSQL, args...).Scan(&total); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscriptions_count_failed"})
                return
        }

        args = append(args, pageSize, (page-1)*pageSize)
        limitIdx := strconv.Itoa(len(args) - 1)
        offsetIdx := strconv.Itoa(len(args))
        rows, err := h.db.Query(ctx, `
                SELECT s.id::text, s.company_id::text, c.name, c.email,
                       s.plan_id::text, p.slug, p.name, p.name_ar,
                       s.status, s.billing_interval,
                       s.current_period_start, s.current_period_end, s.trial_ends_at,
                       s.cancel_at_period_end, s.source, s.created_at
                FROM subscriptions s
                JOIN companies c ON c.id = s.company_id
                JOIN plans p ON p.id = s.plan_id
                WHERE `+whereSQL+`
                ORDER BY s.created_at DESC
                LIMIT $`+limitIdx+` OFFSET $`+offsetIdx, args...)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscriptions_query_failed"})
                return
        }
        defer rows.Close()

        subscriptions := make([]gin.H, 0)
        for rows.Next() {
                var id, companyIDStr, companyName, companyEmail, planID, planSlug, planName, planNameAr string
                var status, billingInterval, source string
                var periodStart, periodEnd, trialEndsAt *time.Time
                var cancelAtPeriodEnd bool
                var createdAt time.Time
                if err := rows.Scan(&id, &companyIDStr, &companyName, &companyEmail,
                        &planID, &planSlug, &planName, &planNameAr,
                        &status, &billingInterval, &periodStart, &periodEnd, &trialEndsAt,
                        &cancelAtPeriodEnd, &source, &createdAt); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscriptions_scan_failed"})
                        return
                }
                subscriptions = append(subscriptions, gin.H{
                        "id": id,
                        "company": gin.H{"id": companyIDStr, "name": companyName, "email": companyEmail},
                        "plan": gin.H{"id": planID, "slug": planSlug, "name": planName, "name_ar": planNameAr},
                        "status":               status,
                        "billing_interval":     billingInterval,
                        "current_period_start": timePtrJSON(periodStart),
                        "current_period_end":   timePtrJSON(periodEnd),
                        "trial_ends_at":        timePtrJSON(trialEndsAt),
                        "cancel_at_period_end": cancelAtPeriodEnd,
                        "source":               source,
                        "created_at":           createdAt.UTC().Format(time.RFC3339),
                })
        }
        c.JSON(http.StatusOK, gin.H{
                "data": subscriptions,
                "pagination": gin.H{"total": total, "page": page, "page_size": pageSize},
        })
}

// CreatePlatformSubscription assigns a plan to a company manually. Any
// live subscription is cancelled first (one live row per company); the new
// row is inserted with source='manual'. Optional trial_days creates a
// trial instead of a paid period.
func (h *Handler) CreatePlatformSubscription(c *gin.Context) {
        var body struct {
                CompanyID       string     `json:"company_id"`
                PlanID          string     `json:"plan_id"`
                BillingInterval string     `json:"billing_interval"`
                PeriodEnd       *time.Time `json:"current_period_end"`
                TrialDays       int        `json:"trial_days"`
        }
        if err := c.ShouldBindJSON(&body); err != nil || body.CompanyID == "" || body.PlanID == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "company_id و plan_id مطلوبان"})
                return
        }
        if body.BillingInterval == "" {
                body.BillingInterval = models.BillingIntervalNone
        }
        if body.BillingInterval != models.BillingIntervalNone &&
                body.BillingInterval != models.BillingIntervalMonthly &&
                body.BillingInterval != models.BillingIntervalYearly {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_interval", "message": "دورية الفوترة غير صالحة"})
                return
        }
        if body.TrialDays < 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_trial_days"})
                return
        }

        principal, _ := auth.PrincipalFromContext(c)
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        // plan must exist and be active
        var planSlug, planName string
        if err := tx.QueryRow(ctx, `
                SELECT slug, name FROM plans WHERE id = $1 AND deleted_at IS NULL AND is_active = TRUE
        `, body.PlanID).Scan(&planSlug, &planName); err != nil {
                if err == pgx.ErrNoRows {
                        c.JSON(http.StatusNotFound, gin.H{"error": "plan_not_found", "message": "الخطة غير موجودة أو غير مفعلة"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_lookup_failed"})
                return
        }

        // company must exist
        var companyName string
        if err := tx.QueryRow(ctx, `
                SELECT name FROM companies WHERE id = $1 AND deleted_at IS NULL
        `, body.CompanyID).Scan(&companyName); err != nil {
                if err == pgx.ErrNoRows {
                        c.JSON(http.StatusNotFound, gin.H{"error": "company_not_found"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "company_lookup_failed"})
                return
        }

        newStatus := models.SubStatusActive
        var trialEndsAt *time.Time
        periodStart := time.Now()
        var periodEnd *time.Time
        if body.TrialDays > 0 {
                newStatus = models.SubStatusTrial
                t := periodStart.AddDate(0, 0, body.TrialDays)
                trialEndsAt = &t
        } else if body.PeriodEnd != nil {
                periodEnd = body.PeriodEnd
        }

        // Cancel any live rows FIRST — the partial unique index allows only one
        // live subscription per company, so the new row cannot coexist with the
        // old one even for a single statement.
        if _, err := tx.Exec(ctx, `
                UPDATE subscriptions SET status = 'cancelled', updated_at = NOW()
                WHERE company_id = $1 AND status IN ('trial','active','pending')
        `, body.CompanyID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_cleanup_failed"})
                return
        }

        var subscriptionID string
        if err := tx.QueryRow(ctx, `
                INSERT INTO subscriptions
                    (company_id, plan_id, status, billing_interval,
                     current_period_start, current_period_end, trial_ends_at, source)
                VALUES ($1, $2, $3, $4, $5, $6, $7, 'manual')
                RETURNING id::text
        `, body.CompanyID, body.PlanID, newStatus, body.BillingInterval,
                periodStart, periodEnd, trialEndsAt).Scan(&subscriptionID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{
                        "error": "subscription_insert_failed", "detail": err.Error(),
                })
                return
        }

        // Keep the legacy display column + company status in sync.
        companyStatus := "active"
        if newStatus == models.SubStatusTrial {
                companyStatus = "trial"
        }
        if _, err := tx.Exec(ctx, `
                UPDATE companies SET plan = $2::text, status = $3, updated_at = NOW()
                WHERE id = $1
        `, body.CompanyID, planSlug, companyStatus); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{
                        "error": "company_sync_failed", "detail": err.Error(),
                })
                return
        }

        _ = writeAuditLog(ctx, tx, principal, "subscription.assign", "billing", "subscription", subscriptionID,
                map[string]any{"company_id": body.CompanyID, "plan": planSlug, "status": newStatus},
                "إسناد خطة " + planName + " إلى " + companyName)
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_commit_failed"})
                return
        }
        h.subs.Invalidate(body.CompanyID)
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "id": subscriptionID, "status": newStatus, "plan": planSlug,
        }})
}

// UpdatePlatformSubscription applies a lifecycle action:
// extend | set_period_end | cancel | suspend | reactivate.
func (h *Handler) UpdatePlatformSubscription(c *gin.Context) {
        id := c.Param("id")
        var body struct {
                Action            string     `json:"action"`
                CurrentPeriodEnd  *time.Time `json:"current_period_end"`
                CancelAtPeriodEnd *bool      `json:"cancel_at_period_end"`
        }
        if err := c.ShouldBindJSON(&body); err != nil || body.Action == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "action مطلوب"})
                return
        }

        principal, _ := auth.PrincipalFromContext(c)
        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var companyID, planSlug, status string
        if err := tx.QueryRow(ctx, `
                SELECT s.company_id::text, p.slug, s.status
                FROM subscriptions s JOIN plans p ON p.id = s.plan_id
                WHERE s.id = $1
        `, id).Scan(&companyID, &planSlug, &status); err != nil {
                if err == pgx.ErrNoRows {
                        c.JSON(http.StatusNotFound, gin.H{"error": "subscription_not_found"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_lookup_failed"})
                return
        }

        summary := ""
        switch body.Action {
        case "extend", "set_period_end":
                if body.CurrentPeriodEnd == nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "period_end_required", "message": "تاريخ نهاية الفترة مطلوب"})
                        return
                }
                if _, err := tx.Exec(ctx, `
                        UPDATE subscriptions SET status = 'active', current_period_end = $2,
                               cancel_at_period_end = COALESCE($3, cancel_at_period_end), updated_at = NOW()
                        WHERE id = $1 AND status IN ('trial','active','expired','suspended')
                `, id, body.CurrentPeriodEnd, body.CancelAtPeriodEnd); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_extend_failed"})
                        return
                }
                if _, err := tx.Exec(ctx, `
                        UPDATE companies SET status = 'active', updated_at = NOW() WHERE id = $1
                `, companyID); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "company_sync_failed"})
                        return
                }
                summary = "تمديد اشتراك " + planSlug
        case "cancel":
                if _, err := tx.Exec(ctx, `
                        UPDATE subscriptions SET status = 'cancelled', updated_at = NOW() WHERE id = $1
                `, id); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_cancel_failed"})
                        return
                }
                summary = "إلغاء اشتراك " + planSlug
        case "suspend":
                if _, err := tx.Exec(ctx, `
                        UPDATE subscriptions SET status = 'suspended', updated_at = NOW() WHERE id = $1
                `, id); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_suspend_failed"})
                        return
                }
                if _, err := tx.Exec(ctx, `
                        UPDATE companies SET status = 'suspended', updated_at = NOW() WHERE id = $1
                `, companyID); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "company_sync_failed"})
                        return
                }
                summary = "تعليق اشتراك " + planSlug
        case "reactivate":
                if _, err := tx.Exec(ctx, `
                        UPDATE subscriptions SET status = 'active', updated_at = NOW() WHERE id = $1
                        AND status IN ('suspended','expired','cancelled')
                `, id); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_reactivate_failed"})
                        return
                }
                if _, err := tx.Exec(ctx, `
                        UPDATE companies SET status = 'active', updated_at = NOW() WHERE id = $1
                `, companyID); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "company_sync_failed"})
                        return
                }
                summary = "إعادة تفعيل اشتراك " + planSlug
        case "set_cancel_at_period_end":
                if body.CancelAtPeriodEnd == nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "cancel_flag_required"})
                        return
                }
                if _, err := tx.Exec(ctx, `
                        UPDATE subscriptions SET cancel_at_period_end = $2, updated_at = NOW() WHERE id = $1
                `, id, *body.CancelAtPeriodEnd); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_flag_failed"})
                        return
                }
                summary = "ضبط الإلغاء عند نهاية الفترة"
        default:
                c.JSON(http.StatusBadRequest, gin.H{"error": "unknown_action", "message": "إجراء غير معروف"})
                return
        }

        _ = writeAuditLog(ctx, tx, principal, "subscription."+body.Action, "billing", "subscription", id,
                map[string]any{"action": body.Action, "from_status": status}, summary)
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_commit_failed"})
                return
        }
        h.subs.Invalidate(companyID)
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id, "action": body.Action}})
}

// CreateManualPayment registers an out-of-band payment (bank transfer,
// cash, retail aggregator) and applies the SAME subscription transition a
// future Paymob webhook will perform — so switching providers never
// changes billing semantics. provider='manual', status='succeeded'.
func (h *Handler) CreateManualPayment(c *gin.Context) {
        var body struct {
                CompanyID       string `json:"company_id"`
                PlanID          string `json:"plan_id"`
                BillingInterval string `json:"billing_interval"`
                AmountPiastres  int64  `json:"amount_piastres"`
                Note            string `json:"note"`
        }
        if err := c.ShouldBindJSON(&body); err != nil || body.CompanyID == "" || body.PlanID == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "company_id و plan_id مطلوبان"})
                return
        }
        if body.BillingInterval != models.BillingIntervalMonthly && body.BillingInterval != models.BillingIntervalYearly {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_interval", "message": "اختر فوترة شهرية أو سنوية"})
                return
        }

        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var planSlug, planName string
        var monthly, yearly int64
        if err := tx.QueryRow(ctx, `
                SELECT slug, name, monthly_price_piastres, yearly_price_piastres
                FROM plans WHERE id = $1 AND deleted_at IS NULL
        `, body.PlanID).Scan(&planSlug, &planName, &monthly, &yearly); err != nil {
                if err == pgx.ErrNoRows {
                        c.JSON(http.StatusNotFound, gin.H{"error": "plan_not_found"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_lookup_failed"})
                return
        }
        amount := body.AmountPiastres
        if amount <= 0 {
                if body.BillingInterval == models.BillingIntervalYearly {
                        amount = yearly
                } else {
                        amount = monthly
                }
        }

        principal, _ := auth.PrincipalFromContext(c)

        // The payment ledger row — succeeded immediately (manual confirmation
        // by the super admin IS the proof on the manual path).
        var paymentID string
        if err := tx.QueryRow(ctx, `
                INSERT INTO payments (company_id, plan_id, billing_interval,
                                      amount_piastres, provider, status, metadata)
                VALUES ($1, $2, $3, $4, 'manual', 'succeeded',
                        jsonb_build_object('note', NULLIF($5, '')::text, 'actor', $6::text))
                RETURNING id::text
        `, body.CompanyID, body.PlanID, body.BillingInterval, amount,
                strings.TrimSpace(body.Note), principal.Email).Scan(&paymentID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{
                        "error": "payment_insert_failed", "detail": err.Error(),
                })
                return
        }

        // Shared transition logic — identical to the Paymob webhook path
        // (extend / convert trial / replace), then the payment row links to
        // the subscription and the legacy display columns stay in sync.
        subscriptionID, err := applySucceededPaymentTx(ctx, tx, body.CompanyID, body.PlanID, body.BillingInterval, paymentID)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{
                        "error": "payment_apply_failed", "detail": err.Error(),
                })
                return
        }

        _ = writeAuditLog(ctx, tx, principal, "payment.manual", "billing", "payment", paymentID,
                map[string]any{"company_id": body.CompanyID, "plan": planSlug, "amount_piastres": amount},
                "تسجيل دفع يدوي لخطة " + planName)
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_commit_failed"})
                return
        }
        h.subs.Invalidate(body.CompanyID)
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "payment_id":      paymentID,
                "subscription_id": subscriptionID,
                "amount_piastres": amount,
                "status":          "succeeded",
        }})
}
