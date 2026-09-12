// Pharmacy-realm subscription endpoints (Task 90 — SaaS plans).
//
// GET /pharmacy/subscription — the current plan, status, usage meters and
//   days left. This endpoint is part of the lockout allow-list: an expired
//   or suspended company must always be able to see its own state (and the
//   plans list below) so it can recover. It therefore performs NO status
//   gate — it reports the status instead.
// GET /pharmacy/plans — the public catalog for the upgrade page, sourced
//   entirely from the plans the super admin created. No code releases are
//   needed to change what customers are offered.
package handlers

import (
	"net/http"
	"sort"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/pharmacy-os/backend/internal/auth"
	"github.com/pharmacy-os/backend/internal/models"
)

// GetPharmacySubscription returns the caller company's effective plan.
func (h *Handler) GetPharmacySubscription(c *gin.Context) {
	if h.subs == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "subscription_system_unavailable", "message": "نظام الاشتراكات غير مهيأ",
		})
		return
	}
	principal, ok := auth.PrincipalFromContext(c)
	if !ok || principal.ID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication_required"})
		return
	}
	companyID := h.companyIDForGate(c, principal)
	if companyID == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "company_scope_unresolved", "message": "تعذر تحديد شركة الجلسة"})
		return
	}

	ctx := c.Request.Context()
	eff, err := h.subs.GetEffective(ctx, companyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "subscription_query_failed", "message": "تعذر جلب بيانات الاشتراك",
		})
		return
	}
	usage, err := h.subs.UsageAll(ctx, companyID)
	if err != nil {
		usage = map[string]int{}
	}

	daysLeft := 0
	var deadline *time.Time
	if eff.Status == models.SubStatusTrial && eff.TrialEndsAt != nil {
		deadline = eff.TrialEndsAt
	} else if eff.Status == models.SubStatusActive && eff.PeriodEnd != nil {
		deadline = eff.PeriodEnd
	}
	if deadline != nil {
		daysLeft = int(time.Until(*deadline).Hours() / 24)
		if daysLeft < 0 {
			daysLeft = 0
		}
	}

	features := make([]string, 0, len(eff.Features))
	for key, on := range eff.Features {
		if on {
			features = append(features, key)
		}
	}
	sort.Strings(features)

	c.JSON(http.StatusOK, gin.H{"data": gin.H{
		"subscription": gin.H{
			"id":                   eff.SubscriptionID,
			"status":               eff.Status,
			"billing_interval":     eff.BillingInterval,
			"current_period_start": timePtrJSON(eff.PeriodStart),
			"current_period_end":   timePtrJSON(eff.PeriodEnd),
			"trial_ends_at":        timePtrJSON(eff.TrialEndsAt),
			"cancel_at_period_end": eff.CancelAtPeriodEnd,
			"days_left":            daysLeft,
		},
		"plan": gin.H{
			"id":                      eff.PlanID,
			"slug":                    eff.PlanSlug,
			"name":                    eff.PlanName,
			"name_ar":                 eff.PlanNameAr,
			"currency":                eff.Currency,
			"monthly_price_piastres":  eff.MonthlyPrice,
			"yearly_price_piastres":   eff.YearlyPrice,
			"features":                features,
			"limits":                  eff.Limits,
		},
		"usage": usage,
	}})
}

// ListPublicPlans returns active, public plans for the upgrade page.
func (h *Handler) ListPublicPlans(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT p.id::text, p.slug, p.name, COALESCE(p.name_ar, ''),
		       COALESCE(p.description, ''),
		       p.monthly_price_piastres, p.yearly_price_piastres, p.currency,
		       p.sort_order,
		       COALESCE(
		           (SELECT jsonb_agg(pf.feature_key ORDER BY pf.feature_key)
		            FROM plan_features pf WHERE pf.plan_id = p.id),
		           '[]'::jsonb),
		       COALESCE(
		           (SELECT jsonb_object_agg(pl.limit_key, pl.value)
		            FROM plan_limits pl WHERE pl.plan_id = p.id),
		           '{}'::jsonb)
		FROM plans p
		WHERE p.is_active = TRUE AND p.is_public = TRUE AND p.deleted_at IS NULL
		ORDER BY p.sort_order, p.created_at
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "plans_query_failed", "message": "تعذر جلب قائمة الخطط",
		})
		return
	}
	defer rows.Close()

	plans := make([]gin.H, 0)
	for rows.Next() {
		var id, slug, name, nameAr, description, currency string
		var monthly, yearly int64
		var sortOrder int
		var featuresRaw, limitsRaw []byte
		if err := rows.Scan(&id, &slug, &name, &nameAr, &description,
			&monthly, &yearly, &currency, &sortOrder,
			&featuresRaw, &limitsRaw); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "plans_scan_failed"})
			return
		}
		features, limits := decodePlanSets(featuresRaw, limitsRaw)
		plans = append(plans, gin.H{
			"id":                     id,
			"slug":                   slug,
			"name":                   name,
			"name_ar":                nameAr,
			"description":            description,
			"monthly_price_piastres": monthly,
			"yearly_price_piastres":  yearly,
			"currency":               currency,
			"sort_order":             sortOrder,
			"features":               features,
			"limits":                 limits,
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "plans_iterate_failed"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": plans})
}

func timePtrJSON(t *time.Time) interface{} {
	if t == nil {
		return nil
	}
	return t.UTC().Format(time.RFC3339)
}
