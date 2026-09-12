// Subscription plan gate helpers (Task 90) — shared by every permission
// check and creation endpoint. The plan is the company ceiling; the wiring
// lives here so both the pharmacy and company realms behave identically.
package handlers

import (
        "github.com/gin-gonic/gin"
        "github.com/pharmacy-os/backend/internal/auth"
)

// companyIDForGate resolves the company whose plan bounds this request.
// company users carry company_id on the principal; employees are
// pharmacy-scoped and resolve through pharmacy → account → company
// (cached inside the subscription service — the mapping is stable).
func (h *Handler) companyIDForGate(c *gin.Context, principal *auth.Principal) string {
        if principal == nil {
                return ""
        }
        if principal.CompanyID != "" {
                return principal.CompanyID
        }
        if h.subs == nil || principal.PharmacyID == "" {
                return ""
        }
        companyID, err := h.subs.CompanyIDForPharmacy(c.Request.Context(), principal.PharmacyID)
        if err != nil {
                return ""
        }
        return companyID
}

// enforcePlanGate applies the subscription plan gate to a permission-
// guarded request. Returns true when the request may continue.
//
// Fail-open policy: when the subscription service is not wired (unit
// tests) or the company cannot be resolved, the gate steps aside — the
// existing RBAC check remains the security boundary. A wired service with
// a missing subscription row denies (fail-closed), which is the intended
// commercial behavior.
func (h *Handler) enforcePlanGate(c *gin.Context, principal *auth.Principal, permissionKey string) bool {
        if h.subs == nil {
                return true
        }
        // Platform super admins are never plan-bound.
        if principal.Type == auth.CompanyUserPrincipal && principal.Role == "super_admin" {
                return true
        }
        companyID := h.companyIDForGate(c, principal)
        if companyID == "" {
                return true
        }
        return h.subs.EnforcePermission(c, companyID, permissionKey)
}

// enforcePlanStatus applies only the subscription-status lockout (no
// permission semantics) — used for guarded mutations without a single
// permission key (e.g. onboarding).
func (h *Handler) enforcePlanStatus(c *gin.Context, principal *auth.Principal) bool {
        if h.subs == nil {
                return true
        }
        if principal.Type == auth.CompanyUserPrincipal && principal.Role == "super_admin" {
                return true
        }
        companyID := h.companyIDForGate(c, principal)
        if companyID == "" {
                return true
        }
        return h.subs.EnforceStatus(c, companyID)
}

// enforcePlanLimit aborts with plan_limit_reached when the company is at
// its plan ceiling for limitKey. Returns true when the request may continue.
func (h *Handler) enforcePlanLimit(c *gin.Context, principal *auth.Principal, limitKey string) bool {
        if h.subs == nil {
                return true
        }
        if principal.Type == auth.CompanyUserPrincipal && principal.Role == "super_admin" {
                return true
        }
        companyID := h.companyIDForGate(c, principal)
        if companyID == "" {
                return true
        }
        return h.subs.EnforceLimit(c, companyID, limitKey)
}

// guardPlanStatus wraps a handler with the subscription-status gate (no
// permission semantics) — used by routes that have no single permission
// key but must still respect the expired/suspended lockout.
func (h *Handler) guardPlanStatus(next gin.HandlerFunc) gin.HandlerFunc {
        return func(c *gin.Context) {
                principal, ok := auth.PrincipalFromContext(c)
                if ok && h.enforcePlanStatus(c, principal) {
                        next(c)
                }
        }
}
