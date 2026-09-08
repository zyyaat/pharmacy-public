// Package middleware - Company Tenant Context (Holding Company Level)
// Phase 2 - Multi-Tenant SaaS Architecture
// This file handles company-level tenant isolation using PostgreSQL RLS
//
// CRITICAL: This middleware MUST run AFTER CompanyAuth middleware
// It uses SET LOCAL within a transaction to ensure company isolation with connection pooling
package middleware

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ============================================
// Company Tenant Context Keys
// ============================================

type companyTenantContextKey string

const (
	// CompanyTxKey holds the database transaction for the current request
	CompanyTxKey companyTenantContextKey = "company_db_tx"

	// CompanyDBPoolKey holds the database connection pool
	CompanyDBPoolKey companyTenantContextKey = "company_db_pool"

	// IsSuperAdminKey indicates if user is platform super admin
	IsSuperAdminKey companyTenantContextKey = "is_super_admin"
)

// ============================================
// Company Tenant Configuration
// ============================================

// CompanyTenantConfig holds configuration for company tenant middleware
type CompanyTenantConfig struct {
	// DBPool is the PostgreSQL connection pool
	DBPool *pgxpool.Pool

	// RequireCompanyID if true, will reject requests without company_id
	RequireCompanyID bool

	// AutoCreateTx if true, automatically begins a transaction for each request
	AutoCreateTx bool

	// BypassPaths are paths that don't require company tenant context
	BypassPaths []string
}

// DefaultCompanyTenantConfig returns default company tenant configuration
func DefaultCompanyTenantConfig(dbPool *pgxpool.Pool) *CompanyTenantConfig {
	return &CompanyTenantConfig{
		DBPool:           dbPool,
		RequireCompanyID: true,
		AutoCreateTx:     true,
		BypassPaths: []string{
			"/health",
			"/healthz",
			"/ready",
			"/readyz",
			"/api/v1/companies/auth/login",
			"/api/v1/companies/auth/register",
			"/api/v1/companies/auth/forgot-password",
			"/api/v1/companies/auth/reset-password",
			"/api/v1/public/",
		},
	}
}

// ============================================
// Company Tenant Context Middleware
// ============================================

// CompanyTenantContext creates middleware that:
// 1. Extracts company ID from JWT claims
// 2. Begins a database transaction (if configured)
// 3. Executes SET LOCAL for RLS company isolation
// 4. Ensures transaction is committed/rolled back after request completes
//
// IMPORTANT: This must be placed AFTER CompanyAuth() middleware in the chain
func CompanyTenantContext(config *CompanyTenantConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()

		// Check if this path should bypass company tenant context
		if shouldBypassCompanyPath(c.Request.URL.Path, config.BypassPaths) {
			c.Next()
			return
		}

		// Get company user ID from auth context (set by CompanyAuth middleware)
		companyUserID := GetCompanyUserID(c)
		if companyUserID == "" && config.RequireCompanyID {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "company_auth_required",
				"message": "Company user must be authenticated to access this endpoint",
				"code":    "COMPANY_TENANT_AUTH_REQUIRED",
			})
			return
		}

		// Store DB pool in context for handlers to use
		ctx = context.WithValue(ctx, CompanyDBPoolKey, config.DBPool)
		c.Set("company_db_pool", config.DBPool)

		// If no user ID (optional auth), skip tenant setup
		if companyUserID == "" {
			c.Next()
			return
		}

		// Get company ID and super admin status from JWT claims
		companyID := GetCompanyID(c)
		isSuperAdmin := IsCompanySuperAdmin(c)

		// Validate we have required company info
		if companyID == "" && config.RequireCompanyID {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "no_company_assigned",
				"message": "User is not assigned to any company",
				"code":    "NO_COMPANY_ASSIGNED",
			})
			return
		}

		// Set company-level context in Gin context
		c.Set("is_super_admin", isSuperAdmin)

		// Also set in Go context
		ctx = context.WithValue(ctx, IsSuperAdminKey, isSuperAdmin)

		// Begin transaction and set RLS context if configured
		if config.AutoCreateTx && companyID != "" {
			err := executeWithCompanyTenantContext(ctx, c, config.DBPool, companyID, companyUserID, isSuperAdmin, func() {
				c.Next()
			})

			if err != nil {
				// Error already handled in executeWithCompanyTenantContext
				return
			}
		} else {
			// No automatic transaction - handler must manage its own
			c.Next()
		}
	}
}

// ============================================
// Company Transaction Management
// ============================================

// executeWithCompanyTenantContext manages the transaction lifecycle with proper RLS setup
// This ensures:
// 1. Transaction is properly begun
// 2. SET LOCAL is executed INSIDE the transaction
// 3. Transaction is committed on success or rolled back on error/panic
// 4. Connection is returned to pool clean (no company data leakage)
func executeWithCompanyTenantContext(
	ctx context.Context,
	c *gin.Context,
	pool *pgxpool.Pool,
	companyID string,
	userID string,
	isSuperAdmin bool,
	handlerFunc func(),
) error {
	// Begin transaction
	tx, err := pool.Begin(ctx)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
			"error":   "transaction_failed",
			"message": "Failed to begin database transaction",
			"code":    "COMPANY_TX_BEGIN_ERROR",
		})
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	// Ensure rollback on panic (safety net)
	defer func() {
		if r := recover(); r != nil {
			_ = tx.Rollback(ctx)
			panic(r) // Re-panic after cleanup
		}
	}()

	// CRITICAL: Execute SET LOCAL inside the transaction
	// This sets the company context for RLS policies
	err = setCompanyTenantContextVariables(ctx, tx, companyID, userID, isSuperAdmin)
	if err != nil {
		_ = tx.Rollback(ctx)
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
			"error":   "company_tenant_context_failed",
			"message": "Failed to set company tenant context",
			"code":    "COMPANY_SET_LOCAL_ERROR",
		})
		return fmt.Errorf("failed to set company tenant context: %w", err)
	}

	// Store transaction in context for handlers to use
	ctx = context.WithValue(ctx, CompanyTxKey, tx)
	c.Set("company_db_tx", tx)
	c.Request = c.Request.WithContext(ctx)

	// Execute the handler
	handlerFunc()

	// A successful JSON response also writes to the response writer. Only
	// rollback when the handler explicitly aborted the context.
	if c.IsAborted() {
		_ = tx.Rollback(ctx)
		return errors.New("request aborted, rolling back")
	}

	// Commit transaction
	if err = tx.Commit(ctx); err != nil {
		_ = tx.Rollback(ctx) // Try rollback if commit fails
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
			"error":   "commit_failed",
			"message": "Failed to commit transaction",
			"code":    "COMPANY_TX_COMMIT_ERROR",
		})
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// setCompanyTenantContextVariables executes SET LOCAL commands for company-level RLS
// All SET LOCAL commands must be inside a transaction
func setCompanyTenantContextVariables(
	ctx context.Context,
	tx pgx.Tx,
	companyID string,
	userID string,
	isSuperAdmin bool,
) error {
	// Set company ID as primary tenant identifier
	_, err := tx.Exec(ctx, "SET LOCAL app.current_company_id = $1", companyID)
	if err != nil {
		return fmt.Errorf("failed to set company_id: %w", err)
	}

	// Set current user ID (for audit trails)
	_, err = tx.Exec(ctx, "SET LOCAL app.current_user_id = $1", userID)
	if err != nil {
		return fmt.Errorf("failed to set user_id: %w", err)
	}

	// Set super admin flag (for RLS policies that allow super admin access)
	_, err = tx.Exec(ctx, "SET LOCAL app.is_super_admin = $1", isSuperAdmin)
	if err != nil {
		return fmt.Errorf("failed to set is_super_admin: %w", err)
	}

	// Note: Additional context variables can be set here:
	// - app.user_role (for role-based logic in DB)
	// - app.request_id (for tracing)
	// - app.bypass_rls (for system admin operations - USE WITH CAUTION)

	return nil
}

// ============================================
// Company User Lookup
// ============================================

// lookupCompanyUserInfo queries the database to get company information for a user
// This runs OUTSIDE any company tenant transaction (uses direct pool connection)
func lookupCompanyUserInfo(
	ctx context.Context,
	pool *pgxpool.Pool,
	companyUserID string,
) (companyID, email, role string, permissionVersion int, isActive bool, err error) {
	const query = `
                SELECT 
                        cu.company_id,
                        cu.email,
                        cu.role,
                        cu.permission_version,
                        cu.is_active
                FROM company_users cu
                WHERE cu.id = $1 
                  AND cu.deleted_at IS NULL
                LIMIT 1
        `

	row := pool.QueryRow(ctx, query, companyUserID)

	var compID, userEmail, userRole *string
	var permVersion *int
	var active *bool

	err = row.Scan(&compID, &userEmail, &userRole, &permVersion, &active)
	if err != nil {
		return "", "", "", 0, false, fmt.Errorf("failed to query company user: %w", err)
	}

	// Handle NULL values
	if compID != nil {
		companyID = *compID
	}
	if userEmail != nil {
		email = *userEmail
	}
	if userRole != nil {
		role = *userRole
	}
	if permVersion != nil {
		permissionVersion = *permVersion
	}
	if active != nil {
		isActive = *active
	}

	return companyID, email, role, permissionVersion, isActive, nil
}

// lookupCompanyUserByEmail looks up company user by email (for login)
func lookupCompanyUserByEmail(
	ctx context.Context,
	pool *pgxpool.Pool,
	email string,
	companyID string,
) (userID, passwordHash, firstName, lastName, role string, loginAttempts int, lockedUntil *interface{}, isActive bool, err error) {
	const query = `
                SELECT 
                        cu.id,
                        cu.password_hash,
                        cu.first_name,
                        cu.last_name,
                        cu.role,
                        cu.login_attempts,
                        cu.locked_until,
                        cu.is_active
                FROM company_users cu
                WHERE cu.email = $1 
                  AND cu.company_id = $2
                  AND cu.deleted_at IS NULL
                LIMIT 1
        `

	row := pool.QueryRow(ctx, query, email, companyID)

	var uid, pHash, fName, lName, r *string
	var attempts *int
	var lockUntil *interface{}
	var active *bool

	err = row.Scan(&uid, &pHash, &fName, &lName, &r, &attempts, &lockUntil, &active)
	if err != nil {
		return "", "", "", "", "", 0, nil, false, fmt.Errorf("failed to query company user by email: %w", err)
	}

	if uid != nil {
		userID = *uid
	}
	if pHash != nil {
		passwordHash = *pHash
	}
	if fName != nil {
		firstName = *fName
	}
	if lName != nil {
		lastName = *lName
	}
	if r != nil {
		role = *r
	}
	if attempts != nil {
		loginAttempts = *attempts
	}
	if lockUntil != nil {
		lockedUntil = lockUntil
	}
	if active != nil {
		isActive = *active
	}

	return userID, passwordHash, firstName, lastName, role, loginAttempts, lockedUntil, isActive, nil
}

// shouldBypassCompanyPath checks if path should skip company tenant context
func shouldBypassCompanyPath(path string, bypassPaths []string) bool {
	for _, bypassPath := range bypassPaths {
		if path == bypassPath || (len(path) > len(bypassPath) && path[:len(bypassPath)] == bypassPath) {
			return true
		}
	}
	return false
}

// ============================================
// Getter Functions for Company Tenant Context
// ============================================

// GetCompanyDBPool extracts database pool from company context
func GetCompanyDBPool(c *gin.Context) (*pgxpool.Pool, bool) {
	pool, exists := c.Get("company_db_pool")
	if !exists {
		return nil, false
	}

	dbPool, ok := pool.(*pgxpool.Pool)
	return dbPool, ok
}

// GetCompanyTransaction extracts current company transaction from context
func GetCompanyTransaction(c *gin.Context) (interface {
	QueryRow(ctx context.Context, sql string, args ...interface{}) interface{}
	Exec(ctx context.Context, sql string, args ...interface{}) (interface{}, error)
}, bool) {
	tx, exists := c.Get("company_db_tx")
	if !exists {
		return nil, false
	}

	if dbTx, ok := tx.(interface {
		QueryRow(ctx context.Context, sql string, args ...interface{}) interface{}
		Exec(ctx context.Context, sql string, args ...interface{}) (interface{}, error)
	}); ok {
		return dbTx, true
	}

	return nil, false
}

// GetCompanyTx returns the pgx.Tx for company-level queries
// This is the preferred method for new code
func GetCompanyTx(c *gin.Context) (pgx.Tx, bool) {
	tx, exists := c.Get("company_db_tx")
	if !exists {
		return nil, false
	}

	dbTx, ok := tx.(pgx.Tx)
	return dbTx, ok
}

// RequireCompanyTenant creates middleware that ensures company tenant context is present
func RequireCompanyTenant() gin.HandlerFunc {
	return func(c *gin.Context) {
		companyID := GetCompanyID(c)
		if companyID == "" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "company_tenant_required",
				"message": "This endpoint requires company tenant context",
				"code":    "COMPANY_TENANT_CONTEXT_MISSING",
			})
			return
		}
		c.Next()
	}
}
