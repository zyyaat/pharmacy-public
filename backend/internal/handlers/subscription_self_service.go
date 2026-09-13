// Tenant self-service billing (Task 90 — subscriptions best-practice pass).
//
// Global best practice: customers must be able to cancel WITHOUT calling
// support (self-service cancellation flows measurably reduce churn and
// support load), and the cancellation must be polite — "cancel at period
// end" keeps paid access until the period actually ends, then the existing
// lazy-expiry locks the account naturally. Resume flips the flag back.
// Both actions are flags on the LIVE subscription: reversible, auditable
// through the subscription row itself, and never touch money.
//
//	POST /pharmacy/subscription/cancel  — cancel_at_period_end = TRUE
//	POST /pharmacy/subscription/resume  — cancel_at_period_end = FALSE
//	GET  /pharmacy/subscription/payments — this company's payment history
//
// All three sit behind settings.billing (granted to EVERY plan by design —
// a company must always be able to manage its own billing) + the mutation
// principal + CSRF on the writes.
package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/pharmacy-os/backend/internal/auth"
	"github.com/pharmacy-os/backend/internal/models"
)

func (h *Handler) setCancelAtPeriodEnd(c *gin.Context, value bool) {
	if h.subs == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "subscription_system_unavailable"})
		return
	}
	principal, ok := auth.PrincipalFromContext(c)
	if !ok || principal.ID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication_required"})
		return
	}
	companyID := h.companyIDForGate(c, principal)
	if companyID == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "company_scope_unresolved"})
		return
	}

	ctx := c.Request.Context()
	var subscriptionID, status string
	err := h.db.QueryRow(ctx, `
		SELECT id::text, status
		FROM subscriptions
		WHERE company_id = $1 AND status IN ('trial','active','pending')
		ORDER BY created_at DESC
		LIMIT 1
	`, companyID).Scan(&subscriptionID, &status)
	if err == pgx.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "subscription_not_found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_lookup_failed"})
		return
	}
	if status == models.SubStatusPending {
		c.JSON(http.StatusConflict, gin.H{
			"error":   "subscription_pending",
			"message": "بانتظار تأكيد الدفع — لا يمكن تغيير الإلغاء الآن",
		})
		return
	}

	if _, err := h.db.Exec(ctx, `
		UPDATE subscriptions SET cancel_at_period_end = $2, updated_at = NOW()
		WHERE id = $1
	`, subscriptionID, value); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "subscription_update_failed"})
		return
	}
	h.subs.Invalidate(companyID)
	c.JSON(http.StatusOK, gin.H{"data": gin.H{
		"id":                   subscriptionID,
		"cancel_at_period_end": value,
	}})
}

// CancelPharmacySubscription — self-service "cancel at period end": access
// continues until the paid period ends, then standard expiry applies.
func (h *Handler) CancelPharmacySubscription(c *gin.Context) {
	h.setCancelAtPeriodEnd(c, true)
}

// ResumePharmacySubscription — undo a pending cancellation.
func (h *Handler) ResumePharmacySubscription(c *gin.Context) {
	h.setCancelAtPeriodEnd(c, false)
}

// ListPharmacyPayments returns this company's payment history (both online
// and manually registered by the super admin) — the receipt trail every
// subscription surface should show.
func (h *Handler) ListPharmacyPayments(c *gin.Context) {
	principal, ok := auth.PrincipalFromContext(c)
	if !ok || principal.ID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication_required"})
		return
	}
	companyID := h.companyIDForGate(c, principal)
	if companyID == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "company_scope_unresolved"})
		return
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT p.id::text, p.plan_id::text, pl.name, COALESCE(pl.name_ar, ''),
		       p.billing_interval, p.amount_piastres, p.currency,
		       p.provider, p.status, p.created_at
		FROM payments p
		JOIN plans pl ON pl.id = p.plan_id
		WHERE p.company_id = $1
		ORDER BY p.created_at DESC
		LIMIT 50
	`, companyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "payments_query_failed"})
		return
	}
	defer rows.Close()

	payments := make([]gin.H, 0)
	for rows.Next() {
		var id, planID, planName, planNameAr, interval, currency, provider, status string
		var amount int64
		var createdAt time.Time
		if err := rows.Scan(&id, &planID, &planName, &planNameAr,
			&interval, &amount, &currency, &provider, &status, &createdAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "payments_scan_failed"})
			return
		}
		payments = append(payments, gin.H{
			"id":               id,
			"plan":             gin.H{"id": planID, "name": planName, "name_ar": planNameAr},
			"billing_interval": interval,
			"amount_piastres":  amount,
			"currency":         currency,
			"provider":         provider,
			"status":           status,
			"created_at":       createdAt.UTC().Format(time.RFC3339),
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "payments_iterate_failed"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": payments})
}
