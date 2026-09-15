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
        "context"
        "errors"
        "log"
        "net/http"
        "strconv"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/jackc/pgx/v5/pgconn"
        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
)

// uniqueViolation reports PostgreSQL 23505 — the partial unique index
// one_live_subscription_per_company(company_id) WHERE status IN
// ('pending','trial','active') rejects a second live row, which is exactly
// what extend/reactivate create. Proven by scripts/reactivate_conflict_repro.py:
// reactivating an expired row while a stale pending payment-intent row exists
// used to surface as an opaque 500; it is a legitimate admin-facing conflict.
func uniqueViolation(err error) bool {
        var pgErr *pgconn.PgError
        return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// liveBlocker finds the company's OTHER live subscription (pending/trial/
// active) — the row that would break one_live_subscription_per_company when
// reactivate/extend set this row active. Empty status = no blocker.
func liveBlocker(ctx context.Context, tx pgx.Tx, companyID, excludeID string) (string, string, *time.Time, error) {
        var blockerID, blockerStatus string
        var trialEnds *time.Time
        err := tx.QueryRow(ctx, `
                SELECT id::text, status, trial_ends_at
                FROM subscriptions
                WHERE company_id = $1::uuid AND id <> $2::uuid
                  AND status IN ('pending','trial','active')
                ORDER BY created_at DESC
                LIMIT 1
        `, companyID, excludeID).Scan(&blockerID, &blockerStatus, &trialEnds)
        if err == pgx.ErrNoRows {
                return "", "", nil, nil
        }
        if err != nil {
                return "", "", nil, err
        }
        return blockerID, blockerStatus, trialEnds, nil
}

// retireStaleIntent cancels an UNPAID pending payment-intent row atomically
// inside the caller's transaction. A pending intent never granted access and
// never recorded revenue, so retiring it is bookkeeping hygiene, not a
// billing decision — the admin must not have to hunt for an invisible row
// (production evidence: a stale Paymob intent blocked every reactivate with
// an opaque 500, and the blocking row was hidden behind status filters).
func retireStaleIntent(ctx context.Context, tx pgx.Tx, blockerID string) error {
        _, err := tx.Exec(ctx, `
                UPDATE subscriptions SET status = 'cancelled', updated_at = NOW()
                WHERE id = $1::uuid AND status = 'pending'
        `, blockerID)
        return err
}

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

        // Effective view by default: ONE governing row per company (live row
        // if any, else the newest terminal row). Plan switches used to
        // accumulate a row per change — one company showed 3 plans × 3
        // statuses with no visible hierarchy. history=true returns the full
        // per-change ledger instead (versions badge shows the depth).
        history := c.Query("history") == "true"

        var total int
        countSQL := `SELECT COUNT(DISTINCT s.company_id)::int`
        if history {
                countSQL = `SELECT COUNT(*)::int`
        }
        if err := h.db.QueryRow(ctx, countSQL+`
                FROM subscriptions s
                JOIN companies c ON c.id = s.company_id
                WHERE `+whereSQL, args...).Scan(&total); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscriptions_count_failed"})
                return
        }

        args = append(args, pageSize, (page-1)*pageSize)
        limitIdx := strconv.Itoa(len(args) - 1)
        offsetIdx := strconv.Itoa(len(args))

        // Both branches return the same column order (+ versions last) so the
        // scanner below stays shared.
        var listSQL string
        if history {
                listSQL = `
                        SELECT s.id::text, s.company_id::text, c.name, c.email,
                               s.plan_id::text, p.slug, p.name, p.name_ar,
                               s.status, s.billing_interval,
                               s.current_period_start, s.current_period_end, s.trial_ends_at,
                               s.cancel_at_period_end, s.source, s.created_at,
                               0::int AS versions
                        FROM subscriptions s
                        JOIN companies c ON c.id = s.company_id
                        JOIN plans p ON p.id = s.plan_id
                        WHERE ` + whereSQL + `
                        ORDER BY s.created_at DESC
                        LIMIT $` + limitIdx + ` OFFSET $` + offsetIdx
        } else {
                listSQL = `
                        SELECT id, company_id, name, email, plan_id, slug, plan_name, name_ar,
                               status, billing_interval, current_period_start, current_period_end,
                               trial_ends_at, cancel_at_period_end, source, created_at, versions
                        FROM (
                                SELECT DISTINCT ON (s.company_id)
                                       s.id::text AS id, s.company_id::text AS company_id,
                                       c.name AS name, c.email AS email,
                                       s.plan_id::text AS plan_id, p.slug AS slug,
                                       p.name AS plan_name, p.name_ar AS name_ar,
                                       s.status AS status, s.billing_interval AS billing_interval,
                                       s.current_period_start AS current_period_start,
                                       s.current_period_end AS current_period_end,
                                       s.trial_ends_at AS trial_ends_at,
                                       s.cancel_at_period_end AS cancel_at_period_end,
                                       s.source AS source, s.created_at AS created_at,
                                       CASE WHEN s.status IN ('pending','trial','active') THEN 0 ELSE 1 END AS prio,
                                       (SELECT COUNT(*) FROM subscriptions x
                                        WHERE x.company_id = s.company_id)::int AS versions
                                FROM subscriptions s
                                JOIN companies c ON c.id = s.company_id
                                JOIN plans p ON p.id = s.plan_id
                                WHERE ` + whereSQL + `
                                ORDER BY s.company_id, prio, s.created_at DESC
                        ) t
                        ORDER BY t.prio ASC, t.created_at DESC, t.id
                        LIMIT $` + limitIdx + ` OFFSET $` + offsetIdx
        }
        rows, err := h.db.Query(ctx, listSQL, args...)
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
                var versions int
                if err := rows.Scan(&id, &companyIDStr, &companyName, &companyEmail,
                        &planID, &planSlug, &planName, &planNameAr,
                        &status, &billingInterval, &periodStart, &periodEnd, &trialEndsAt,
                        &cancelAtPeriodEnd, &source, &createdAt, &versions); err != nil {
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
                        "versions":             versions,
                })
        }
        c.JSON(http.StatusOK, gin.H{
                "data": subscriptions,
                "pagination": gin.H{"total": total, "page": page, "page_size": pageSize},
        })
}

// CreatePlatformSubscription assigns a plan to a company manually. Plan
// switching is a TRANSITION on the live row (Stripe-style price change),
// not close-then-open: the old flow accumulated one row per switch
// (production evidence: one company ended with 3 rows × 3 plans × 3
// statuses and nobody could tell which row governs). Lifecycle history
// stays in audit_logs. A NEW row is only opened when nothing is live
// (fresh assignment after expiry/cancellation). Optional trial_days
// creates a trial instead of a paid period.
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

        // Transition the live row IN PLACE when one exists — the partial
        // unique index allows only one live row per company, and re-opening a
        // new row per plan change made the ledger unreadable. When no live
        // row exists, open a fresh one (fresh assignment after termination).
        var liveSubID string
        switchErr := tx.QueryRow(ctx, `
                SELECT id::text FROM subscriptions
                WHERE company_id = $1 AND status IN ('trial','active','pending')
                ORDER BY created_at DESC LIMIT 1
        `, body.CompanyID).Scan(&liveSubID)
        hasLive := switchErr == nil
        if switchErr != nil && switchErr != pgx.ErrNoRows {
                log.Printf("[platform-subscriptions] assign live lookup company=%s: %v", body.CompanyID, switchErr)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_lookup_failed"})
                return
        }

        var subscriptionID string
        if hasLive {
                if _, err := tx.Exec(ctx, `
                        UPDATE subscriptions SET plan_id = $2, status = $3, billing_interval = $4,
                               current_period_start = $5, current_period_end = $6, trial_ends_at = $7,
                               cancel_at_period_end = FALSE, updated_at = NOW()
                        WHERE id = $1
                `, liveSubID, body.PlanID, newStatus, body.BillingInterval,
                        periodStart, periodEnd, trialEndsAt); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{
                                "error": "subscription_transition_failed", "detail": err.Error(),
                        })
                        return
                }
                subscriptionID = liveSubID
        } else {
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

        _ = writePlatformAuditLog(ctx, tx, principal, "subscription.assign", "billing", "subscription", subscriptionID, body.CompanyID,
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
        var periodEndPtr *time.Time
        if err := tx.QueryRow(ctx, `
                SELECT s.company_id::text, p.slug, s.status, s.current_period_end
                FROM subscriptions s JOIN plans p ON p.id = s.plan_id
                WHERE s.id = $1
        `, id).Scan(&companyID, &planSlug, &status, &periodEndPtr); err != nil {
                if err == pgx.ErrNoRows {
                        c.JSON(http.StatusNotFound, gin.H{"error": "subscription_not_found"})
                        return
                }
                log.Printf("[platform-subscriptions] lookup db error id=%s: %v", id, err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_lookup_failed"})
                return
        }

        summary := ""
        autoCancelledPending := ""
        switch body.Action {
        case "extend", "set_period_end":
                if body.CurrentPeriodEnd == nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "period_end_required", "message": "تاريخ نهاية الفترة مطلوب"})
                        return
                }
                if status == models.SubStatusTrial {
                        // Extending a TRIAL must extend the trial — never silently
                        // convert it into a paid subscription (explicit state
                        // transitions only; a silent trial→paid flip fabricates revenue).
                        if _, err := tx.Exec(ctx, `
                                UPDATE subscriptions SET trial_ends_at = $2, updated_at = NOW()
                                WHERE id = $1 AND status = 'trial'
                        `, id, body.CurrentPeriodEnd); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_extend_failed"})
                                return
                        }
                        summary = "تمديد تجربة " + planSlug
                } else {
                        blockerID, blockerStatus, _, err := liveBlocker(ctx, tx, companyID, id)
                        if err != nil {
                                log.Printf("[platform-subscriptions] extend blocker lookup error id=%s: %v", id, err)
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_lookup_failed"})
                                return
                        }
                        if blockerStatus == "pending" {
                                if err := retireStaleIntent(ctx, tx, blockerID); err != nil {
                                        log.Printf("[platform-subscriptions] extend retire-stale error id=%s: %v", blockerID, err)
                                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_extend_failed"})
                                        return
                                }
                                autoCancelledPending = blockerID
                        } else if blockerStatus != "" {
                                label := map[string]string{"trial": "تجريبي", "active": "نشط"}[blockerStatus]
                                c.JSON(http.StatusConflict, gin.H{"error": "subscription_conflict",
                                        "message": "لا يمكن التمديد: الشركة لديها اشتراك «" + label + "» حي — ألغِه من القائمة أولًا إن أردت تمديد هذا الصف بدلًا منه"})
                                return
                        }
                        if _, err := tx.Exec(ctx, `
                                UPDATE subscriptions SET status = 'active', current_period_end = $2,
                                       cancel_at_period_end = COALESCE($3, cancel_at_period_end), updated_at = NOW()
                                WHERE id = $1 AND status IN ('active','expired','suspended')
                        `, id, body.CurrentPeriodEnd, body.CancelAtPeriodEnd); err != nil {
                                if uniqueViolation(err) {
                                        c.JSON(http.StatusConflict, gin.H{"error": "subscription_conflict",
                                                "message": "لا يمكن التمديد: توجد حالة اشتراك أخرى «حية» لنفس الشركة — ألغِ تلك الحالة من القائمة أولًا"})
                                        return
                                }
                                log.Printf("[platform-subscriptions] extend db error id=%s: %v", id, err)
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
                }
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
                // One live subscription per company (unique partial index).
                // Resolution policy (product decision after the production
                // 500 report — the admin must never hunt for an invisible
                // blocking row):
                //   pending  → retire it automatically (unpaid intent: no
                //              access ever granted, no revenue recorded) and
                //              proceed — audited as auto_cancelled_pending;
                //   trial/active → refuse with the EXACT state and end date,
                //              because cancelling a live access-granting state
                //              is a real commercial decision, not hygiene.
                // The 23505 guard below remains the race safety net.
                blockerID, blockerStatus, blockerTrialEnd, err := liveBlocker(ctx, tx, companyID, id)
                if err != nil {
                        log.Printf("[platform-subscriptions] blocker lookup error id=%s: %v", id, err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_lookup_failed"})
                        return
                }
                if blockerStatus == "pending" {
                        if err := retireStaleIntent(ctx, tx, blockerID); err != nil {
                                log.Printf("[platform-subscriptions] reactivate retire-stale error id=%s: %v", blockerID, err)
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_reactivate_failed"})
                                return
                        }
                        autoCancelledPending = blockerID
                } else if blockerStatus != "" {
                        label := map[string]string{"trial": "تجريبي", "active": "نشط"}[blockerStatus]
                        hint := map[string]string{
                                "trial":  "ألغِه من القائمة أولًا إن أردت تفعيل هذا الصف بدلًا منه",
                                "active": "الوصول مفتوح أصلًا؛ إن أردت تفعيل هذا الصف بدلًا منه ألغِ الصف النشط أولًا",
                        }[blockerStatus]
                        detail := ""
                        if blockerStatus == "trial" && blockerTrialEnd != nil {
                                detail = " حتى " + blockerTrialEnd.Format("2006-01-02")
                        }
                        c.JSON(http.StatusConflict, gin.H{"error": "subscription_conflict",
                                "message": "لا يمكن إعادة التفعيل: الشركة لديها اشتراك «" + label + "» حي" + detail + " — " + hint})
                        return
                }
                // Reactivation must restore access IMMEDIATELY: reactivating a
                // row whose period end is past (or missing) would be lazily
                // re-expired on the very next read — an invisible no-op trap.
                // Default to a fresh 30-day window unless the admin pins an
                // explicit end date; an existing FUTURE period end is kept.
                effectiveEnd := body.CurrentPeriodEnd
                if effectiveEnd == nil {
                        now := time.Now()
                        if periodEndPtr == nil || !periodEndPtr.After(now) {
                                t := now.AddDate(0, 0, 30)
                                effectiveEnd = &t
                        }
                }
                tag, err := tx.Exec(ctx, `
                        UPDATE subscriptions SET status = 'active',
                               current_period_end = COALESCE($2, current_period_end), updated_at = NOW()
                        WHERE id = $1 AND status IN ('suspended','expired','cancelled')
                `, id, effectiveEnd)
                if err != nil {
                        if uniqueViolation(err) {
                                c.JSON(http.StatusConflict, gin.H{"error": "subscription_conflict",
                                        "message": "لا يمكن إعادة التفعيل: توجد حالة اشتراك أخرى «حية» لنفس الشركة (قيد الانتظار أو تجربة أو نشطة) — ألغِ تلك الحالة من القائمة أولًا ثم أعد التفعيل"})
                                return
                        }
                        log.Printf("[platform-subscriptions] reactivate db error id=%s: %v", id, err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_reactivate_failed"})
                        return
                }
                // صفر صفوف = حالة لا يغطيها الزر أصلًا (مثل trial المنتهية) —
                // كان يُعاد 200 «نجاح» بلا أي تغيير: فخ صامت أثبته إعادة الإنتاج.
                if tag.RowsAffected() == 0 {
                        c.JSON(http.StatusConflict, gin.H{"error": "invalid_state",
                                "message": "لا يمكن إعادة تفعيل الاشتراك في حالته الحالية — حدّث الصفحة وأعد المحاولة أو سجّل دفعة يدوية"})
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

        _ = writePlatformAuditLog(ctx, tx, principal, "subscription."+body.Action, "billing", "subscription", id, companyID,
                map[string]any{"action": body.Action, "from_status": status,
                        "auto_cancelled_pending": autoCancelledPending}, summary)
        if err := tx.Commit(ctx); err != nil {
                log.Printf("[platform-subscriptions] commit error action=%s id=%s: %v", body.Action, id, err)
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
                IdempotencyKey  string `json:"idempotency_key"`
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

        // Idempotency (Stripe-style billing hygiene): a retried or
        // double-clicked submission replays the SAME client-generated key
        // and receives the original payment back instead of
        // double-extending the subscription.
        if key := strings.TrimSpace(body.IdempotencyKey); key != "" {
                var existingID string
                err := tx.QueryRow(ctx, `
                        SELECT id::text FROM payments WHERE idempotency_key = $1
                `, key).Scan(&existingID)
                if err == nil {
                        _ = tx.Rollback(ctx) // read-only replay — nothing to commit
                        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                                "payment_id":      existingID,
                                "subscription_id": "",
                                "amount_piastres": 0,
                                "status":          "succeeded",
                                "duplicate":       true,
                        }})
                        return
                }
                if err != pgx.ErrNoRows {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_lookup_failed"})
                        return
                }
        }

        // The payment ledger row — succeeded immediately (manual confirmation
        // by the super admin IS the proof on the manual path). Phase S1: the
        // confirmation stamp carries source='manual'; NO settlement row —
        // there is no provider to settle with.
        var paymentID string
        if err := tx.QueryRow(ctx, `
                INSERT INTO payments (company_id, plan_id, billing_interval,
                                      amount_piastres, provider, status, metadata, idempotency_key,
                                      confirmed_at, confirmation_source)
                VALUES ($1, $2, $3, $4, 'manual', 'succeeded',
                        jsonb_build_object('note', NULLIF($5, '')::text, 'actor', $6::text), NULLIF($7, '')::text,
                        NOW(), 'manual')
                RETURNING id::text
        `, body.CompanyID, body.PlanID, body.BillingInterval, amount,
                strings.TrimSpace(body.Note), principal.Email,
                strings.TrimSpace(body.IdempotencyKey)).Scan(&paymentID); err != nil {
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

        _ = writePlatformAuditLog(ctx, tx, principal, "payment.manual", "billing", "payment", paymentID, body.CompanyID,
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
