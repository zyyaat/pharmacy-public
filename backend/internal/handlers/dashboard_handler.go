package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/pharmacy-os/backend/internal/auth"
)

// GetDashboardStats returns statistics for the authenticated company scope.
// The scope comes from the session principal; no company id is accepted from
// the browser.
func (h *Handler) GetDashboardStats(c *gin.Context) {
	principal, ok := auth.PrincipalFromContext(c)
	if !ok || principal.Type != auth.CompanyUserPrincipal {
		c.JSON(http.StatusForbidden, gin.H{"error": "company_account_required", "message": "A company account is required"})
		return
	}

	const query = `
		SELECT
			COUNT(*)::int,
			COUNT(*) FILTER (WHERE status = 'active')::int,
			(SELECT COUNT(*)::int FROM company_users cu
			 WHERE ($2::boolean OR cu.company_id = $1) AND cu.deleted_at IS NULL),
			(SELECT COUNT(*)::int FROM company_users cu
			 WHERE ($2::boolean OR cu.company_id = $1) AND cu.deleted_at IS NULL AND cu.is_active),
			(SELECT COUNT(*)::int FROM accounts a
			 WHERE ($2::boolean OR a.company_id = $1) AND a.deleted_at IS NULL)
		FROM companies
		WHERE ($2::boolean OR id = $1) AND deleted_at IS NULL
	`

	var totalCompanies, activeCompanies, totalUsers, activeUsers, totalAccounts int
	if err := h.db.QueryRow(c.Request.Context(), query, principal.CompanyID, principal.Role == "super_admin").
		Scan(&totalCompanies, &activeCompanies, &totalUsers, &activeUsers, &totalAccounts); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "dashboard_query_failed", "message": "Could not load dashboard statistics"})
		return
	}

	activities, err := h.companyActivity(c, principal)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "activity_query_failed", "message": "Could not load recent activity"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"totalCompanies":  totalCompanies,
		"activeCompanies": activeCompanies,
		"totalUsers":      totalUsers,
		"activeUsers":     activeUsers,
		"totalAccounts":   totalAccounts,
		"recentActivity":  activities,
	})
}

// GetRecentActivity returns the same session-scoped activity feed used by the
// dashboard. It intentionally returns an empty list when no audit records
// exist, never fabricated activity.
func (h *Handler) GetRecentActivity(c *gin.Context) {
	principal, ok := auth.PrincipalFromContext(c)
	if !ok || principal.Type != auth.CompanyUserPrincipal {
		c.JSON(http.StatusForbidden, gin.H{"error": "company_account_required", "message": "A company account is required"})
		return
	}
	activities, err := h.companyActivity(c, principal)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "activity_query_failed", "message": "Could not load recent activity"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": activities})
}

type dashboardActivity struct {
	ID          string `json:"id"`
	Type        string `json:"type"`
	Description string `json:"description"`
	UserName    string `json:"userName"`
	Timestamp   string `json:"timestamp"`
}

func (h *Handler) companyActivity(c *gin.Context, principal *auth.Principal) ([]dashboardActivity, error) {
	const query = `
		SELECT
			al.id::text,
			al.action,
			COALESCE(al.changes_summary, al.action),
			COALESCE(NULLIF(al.actor_display_name, ''), NULLIF(al.actor_email, ''), 'System'),
			al.created_at
		FROM audit_logs al
		LEFT JOIN accounts a ON a.id = al.account_id
		WHERE ($2::boolean OR a.company_id = $1)
		  AND ($2::boolean OR al.account_id IS NOT NULL)
		ORDER BY al.created_at DESC
		LIMIT 10
	`

	rows, err := h.db.Query(c.Request.Context(), query, principal.CompanyID, principal.Role == "super_admin")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	activities := make([]dashboardActivity, 0)
	for rows.Next() {
		var item dashboardActivity
		var timestamp time.Time
		if err := rows.Scan(&item.ID, &item.Type, &item.Description, &item.UserName, &timestamp); err != nil {
			// Keep the query error visible to the client; never silently replace
			// an unavailable activity feed with sample data.
			return nil, err
		}
		item.Timestamp = timestamp.UTC().Format(time.RFC3339)
		activities = append(activities, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return activities, nil
}
