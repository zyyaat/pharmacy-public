package subscription

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/pharmacy-os/backend/internal/models"
)

// Plan gate responses (Task 90). The frontend matches on the "error" field:
//   - subscription_expired / subscription_suspended / subscription_pending:
//     the account itself is blocked → redirect to the subscription page
//     (the only always-allowed surface besides auth).
//   - plan_permission_denied: the plan simply does not include the key.
//   - plan_limit_reached: a creation endpoint hit its ceiling.

// EnforcePermission applies the full plan gate for a permission key:
//  1. the live subscription status must be trial/active;
//  2. the plan must include the permission key.
// It aborts with a structured 403 and returns false when blocked.
func (s *Service) EnforcePermission(c *gin.Context, companyID, permissionKey string) bool {
	eff, err := s.GetEffective(c.Request.Context(), companyID)
	if err != nil {
		abortSubscription(c, http.StatusForbidden, "subscription_missing",
			"لا يوجد اشتراك مرتبط بهذه الشركة", "SUBSCRIPTION_MISSING")
		return false
	}
	if !statusActive(eff) {
		abortStatus(c, eff.Status)
		return false
	}
	if !eff.HasPermission(permissionKey) {
		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
			"error":               "plan_permission_denied",
			"message":             "هذه الصلاحية غير متاحة في خطة الاشتراك الحالية",
			"code":                "PLAN_PERMISSION_DENIED",
			"required_permission": permissionKey,
			"plan":                eff.PlanSlug,
		})
		return false
	}
	return true
}

// EnforceStatus applies only the subscription-status gate (for endpoints
// that have no single permission key but must still respect the lockout,
// e.g. onboarding writes).
func (s *Service) EnforceStatus(c *gin.Context, companyID string) bool {
	eff, err := s.GetEffective(c.Request.Context(), companyID)
	if err != nil {
		abortSubscription(c, http.StatusForbidden, "subscription_missing",
			"لا يوجد اشتراك مرتبط بهذه الشركة", "SUBSCRIPTION_MISSING")
		return false
	}
	if !statusActive(eff) {
		abortStatus(c, eff.Status)
		return false
	}
	return true
}

// EnforceLimit aborts with plan_limit_reached when the company is at or
// over the ceiling for limitKey. Returns false when the request aborted.
func (s *Service) EnforceLimit(c *gin.Context, companyID, limitKey string) bool {
	used, limit, allowed, err := s.CheckLimit(c.Request.Context(), companyID, limitKey)
	if err != nil {
		// A counting failure must not silently block business operations —
		// the permission gate above is the security boundary; limits are
		// commercial ceilings. Log-shaped body so callers can observe it.
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
			"error":     "plan_limit_check_failed",
			"message":   "تعذر التحقق من حدود الخطة",
			"limit_key": limitKey,
		})
		return false
	}
	if !allowed {
		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
			"error":     "plan_limit_reached",
			"message":   "لقد وصلت إلى الحد الأقصى المسموح في خطتك الحالية — قم بالترقية للاستمرار",
			"code":      "PLAN_LIMIT_REACHED",
			"limit_key": limitKey,
			"limit":     limit,
			"used":      used,
			"plan":      s.currentPlanSlugCached(c, companyID),
		})
		return false
	}
	return true
}

func (s *Service) currentPlanSlugCached(c *gin.Context, companyID string) string {
	eff, err := s.GetEffective(c.Request.Context(), companyID)
	if err != nil {
		return ""
	}
	return eff.PlanSlug
}

// statusActive reports whether the (lazily evaluated) subscription grants
// access. trial/active are the granting states; pending waits for a
// webhook confirmation and grants nothing.
func statusActive(eff *models.EffectivePlan) bool {
	switch eff.Status {
	case models.SubStatusTrial, models.SubStatusActive:
		return true
	default:
		return false
	}
}

func abortStatus(c *gin.Context, status string) {
	switch status {
	case models.SubStatusSuspended:
		abortSubscription(c, http.StatusForbidden, "subscription_suspended",
			"تم تعليق اشتراكك — تواصل مع الدعم أو باشر بالدفع لاستعادة الوصول", "SUBSCRIPTION_SUSPENDED")
	case models.SubStatusPending:
		abortSubscription(c, http.StatusForbidden, "subscription_pending",
			"بانتظار تأكيد الدفع — سيتفعل اشتراكك تلقائيًا فور التأكيد", "SUBSCRIPTION_PENDING")
	default: // expired / cancelled
		abortSubscription(c, http.StatusForbidden, "subscription_expired",
			"انتهت فترة اشتراكك — اختر خطة واشترك لاستعادة الوصول، وبياناتك محفوظة بالكامل", "SUBSCRIPTION_EXPIRED")
	}
}

func abortSubscription(c *gin.Context, code int, errCode, message, upper string) {
	c.AbortWithStatusJSON(code, gin.H{
		"error":   errCode,
		"message": message,
		"code":    upper,
	})
}
