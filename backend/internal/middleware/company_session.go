package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/pharmacy-os/backend/internal/auth"
)

// CompanySessionContext adapts the central opaque-session principal to the
// context keys consumed by the company authorization and tenant helpers.
// It deliberately does not validate a second JWT or create a parallel
// browser authentication system.
func CompanySessionContext() gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := auth.PrincipalFromContext(c)
		if !ok || principal.Type != auth.CompanyUserPrincipal {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "company_account_required",
				"message": "A company account is required for this resource",
			})
			return
		}

		c.Set("company_user_id", principal.ID)
		c.Set("company_user_email", principal.Email)
		c.Set("company_id", principal.CompanyID)
		c.Set("company_role", principal.Role)
		c.Set("company_is_super_admin", principal.Role == "super_admin")
		c.Set("company_permission_version", principal.PermissionVersion)
		c.Set("company_authenticated", true)
		c.Next()
	}
}

// CompanyDBPoolContext makes the shared pool available to the existing
// permission middleware without opting these routes into the unfinished
// legacy JWT/RLS transaction middleware.
func CompanyDBPoolContext(pool *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set("company_db_pool", pool)
		c.Next()
	}
}
