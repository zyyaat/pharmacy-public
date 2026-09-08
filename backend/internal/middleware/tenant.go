// Package middleware provides HTTP middleware for multi-tenancy support
// This file handles Tenant Context isolation using PostgreSQL RLS (Row Level Security)
//
// CRITICAL: This middleware MUST run AFTER the Auth middleware to have access to user context
// It uses SET LOCAL within a transaction to ensure tenant isolation with connection pooling
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

// Context keys for tenant-related data
type tenantContextKey string

const (
	// PharmacyIDKey holds the current pharmacy ID in context
	PharmacyIDKey tenantContextKey = "pharmacy_id"

	// BranchIDKey holds the current branch ID in context
	BranchIDKey tenantContextKey = "branch_id"

	// EmployeeIDKey holds the current employee ID in context
	EmployeeIDKey tenantContextKey = "employee_id"

	// AccountIDKey holds the current account ID in context
	AccountIDKey tenantContextKey = "account_id"

	// TxKey holds the database transaction for the current request
	TxKey tenantContextKey = "db_tx"

	// DBPoolKey holds the database connection pool
	DBPoolKey tenantContextKey = "db_pool"
)

// TenantConfig holds configuration for tenant middleware
type TenantConfig struct {
	// DBPool is the PostgreSQL connection pool (pgxpool.Pool)
	DBPool *pgxpool.Pool

	// RequirePharmacyID if true, will reject requests without pharmacy_id
	RequirePharmacyID bool

	// AutoCreateTx if true, automatically begins a transaction for each request
	AutoCreateTx bool

	// BypassPaths are paths that don't require tenant context (e.g., /health, /api/auth/*)
	BypassPaths []string
}

// DefaultTenantConfig returns default tenant configuration
func DefaultTenantConfig(dbPool *pgxpool.Pool) *TenantConfig {
	return &TenantConfig{
		DBPool:            dbPool,
		RequirePharmacyID: true,
		AutoCreateTx:      true,
		BypassPaths: []string{
			"/health",
			"/healthz",
			"/ready",
			"/readyz",
			"/api/auth/login",
			"/api/auth/callback",
			"/api/auth/refresh",
		},
	}
}

// TenantContext creates middleware that:
// 1. Extracts pharmacy/branch/employee IDs from JWT claims or database lookup
// 2. Begins a database transaction (if configured)
// 3. Executes SET LOCAL for RLS tenant isolation
// 4. Ensures transaction is committed/rolled back after request completes
//
// IMPORTANT: This must be placed after the Go auth middleware in the chain
func TenantContext(config *TenantConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()

		// Check if this path should bypass tenant context
		if shouldBypassPath(c.Request.URL.Path, config.BypassPaths) {
			c.Next()
			return
		}

		// Get user ID from the Go auth context
		userID := GetUserID(c)
		if userID == "" && config.RequirePharmacyID {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "authentication_required",
				"message": "User must be authenticated to access this endpoint",
				"code":    "TENANT_AUTH_REQUIRED",
			})
			return
		}

		// Store DB pool in context for handlers to use
		ctx = context.WithValue(ctx, DBPoolKey, config.DBPool)
		c.Set("db_pool", config.DBPool)

		// If no user ID (optional auth), skip tenant setup
		if userID == "" {
			c.Next()
			return
		}

		// Look up employee record to get pharmacy/branch/account IDs
		// This query runs OUTSIDE the tenant transaction (no RLS yet)
		pharmacyID, branchID, employeeID, accountID, err := lookupEmployeeTenantInfo(ctx, config.DBPool, userID)
		if err != nil {
			// Log error but don't necessarily fail - depends on config
			if config.RequirePharmacyID {
				c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
					"error":   "tenant_lookup_failed",
					"message": "Failed to retrieve tenant information",
					"code":    "TENANT_LOOKUP_ERROR",
				})
				return
			}
			// Continue without tenant context (handler should handle missing tenant)
			c.Next()
			return
		}

		// Validate we have required tenant info
		if pharmacyID == "" && config.RequirePharmacyID {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "no_pharmacy_assigned",
				"message": "User is not assigned to any pharmacy",
				"code":    "NO_PHARMACY_ASSIGNED",
			})
			return
		}

		// Set tenant IDs in Gin context (for easy access in handlers)
		c.Set("pharmacy_id", pharmacyID)
		c.Set("branch_id", branchID)
		c.Set("employee_id", employeeID)
		c.Set("account_id", accountID)

		// Also set in Go context for use outside Gin
		ctx = context.WithValue(ctx, PharmacyIDKey, pharmacyID)
		ctx = context.WithValue(ctx, BranchIDKey, branchID)
		ctx = context.WithValue(ctx, EmployeeIDKey, employeeID)
		ctx = context.WithValue(ctx, AccountIDKey, accountID)

		// Begin transaction and set RLS context if configured
		if config.AutoCreateTx && pharmacyID != "" {
			err := executeWithTenantContext(ctx, c, config.DBPool, pharmacyID, userID, func() {
				c.Next()
			})

			if err != nil {
				// Error already handled in executeWithTenantContext
				return
			}
		} else {
			// No automatic transaction - handler must manage its own
			c.Next()
		}
	}
}

// executeWithTenantContext manages the transaction lifecycle with proper RLS setup
// This ensures:
// 1. Transaction is properly begun
// 2. SET LOCAL is executed INSIDE the transaction
// 3. Transaction is committed on success or rolled back on error/panic
// 4. Connection is returned to pool clean (no tenant leakage)
func executeWithTenantContext(
	ctx context.Context,
	c *gin.Context,
	pool *pgxpool.Pool,
	pharmacyID string,
	userID string,
	handlerFunc func(),
) error {
	// Begin transaction
	tx, err := pool.Begin(ctx)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
			"error":   "transaction_failed",
			"message": "Failed to begin database transaction",
			"code":    "TX_BEGIN_ERROR",
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
	// This sets the tenant context for RLS policies
	// SET LOCAL only lasts for the duration of the transaction
	// When transaction commits/rolls back, value is cleared
	// This prevents tenant data leakage in connection pools
	err = setTenantContextVariables(ctx, tx, pharmacyID, userID)
	if err != nil {
		_ = tx.Rollback(ctx)
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
			"error":   "tenant_context_failed",
			"message": "Failed to set tenant context",
			"code":    "SET_LOCAL_ERROR",
		})
		return fmt.Errorf("failed to set tenant context: %w", err)
	}

	// Store transaction in context for handlers to use
	ctx = context.WithValue(ctx, TxKey, tx)
	c.Set("db_tx", tx)
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
			"code":    "TX_COMMIT_ERROR",
		})
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// setTenantContextVariables executes SET LOCAL commands for RLS
// All SET LOCAL commands must be inside a transaction
func setTenantContextVariables(
	ctx context.Context,
	tx pgx.Tx,
	pharmacyID string,
	userID string,
) error {
	// Set primary tenant identifier
	_, err := tx.Exec(ctx, "SET LOCAL app.current_pharmacy_id = $1", pharmacyID)
	if err != nil {
		return fmt.Errorf("failed to set pharmacy_id: %w", err)
	}

	// Set current user ID (for audit trails and who-am-I queries)
	_, err = tx.Exec(ctx, "SET LOCAL app.current_user_id = $1", userID)
	if err != nil {
		return fmt.Errorf("failed to set user_id: %w", err)
	}

	// Note: Additional context variables can be set here as needed:
	// - app.user_role (for role-based logic in DB)
	// - app.request_id (for tracing)
	// - app.bypass_rls (for system admin operations - USE WITH CAUTION)

	return nil
}

// lookupEmployeeTenantInfo queries the database to get tenant information for an employee
// This runs OUTSIDE any tenant transaction (uses direct pool connection)
func lookupEmployeeTenantInfo(
	ctx context.Context,
	pool *pgxpool.Pool,
	authUserID string,
) (pharmacyID, branchID, employeeID, accountID string, err error) {
	// Query employees table using the Go-authenticated employee UUID
	// We don't use RLS here because we're looking up the tenant itself
	const query = `
                SELECT 
                        e.id as employee_id,
                        e.pharmacy_id,
                        e.branch_id,
                        e.account_id,
                        p.id as verify_pharmacy_id
                FROM employees e
                LEFT JOIN pharmacies p ON e.pharmacy_id = p.id
                WHERE e.id = $1
                  AND e.is_active = true
                LIMIT 1
        `

	row := pool.QueryRow(ctx, query, authUserID)

	var empID, pharmID, branch, accID, verifyPharmID *string

	err = row.Scan(&empID, &pharmID, &branch, &accID, &verifyPharmID)
	if err != nil {
		return "", "", "", "", fmt.Errorf("failed to query employee: %w", err)
	}

	// Handle NULL values
	if empID != nil {
		employeeID = *empID
	}
	if pharmID != nil {
		pharmacyID = *pharmID
	}
	if branch != nil {
		branchID = *branch
	}
	if accID != nil {
		accountID = *accID
	}

	return pharmacyID, branchID, employeeID, accountID, nil
}

// shouldBypassPath checks if the given path should skip tenant context setup
func shouldBypassPath(path string, bypassPaths []string) bool {
	for _, bypassPath := range bypassPaths {
		if path == bypassPath || len(path) > len(bypassPath) && path[:len(bypassPath)] == bypassPath {
			return true
		}
	}
	return false
}

// GetPharmacyID extracts pharmacy ID from Gin context
func GetPharmacyID(c *gin.Context) string {
	if pharmacyID, exists := c.Get("pharmacy_id"); exists {
		if id, ok := pharmacyID.(string); ok {
			return id
		}
	}
	return ""
}

// GetBranchID extracts branch ID from Gin context
func GetBranchID(c *gin.Context) string {
	if branchID, exists := c.Get("branch_id"); exists {
		if id, ok := branchID.(string); ok {
			return id
		}
	}
	return ""
}

// GetEmployeeID extracts employee ID from Gin context
func GetEmployeeID(c *gin.Context) string {
	if employeeID, exists := c.Get("employee_id"); exists {
		if id, ok := employeeID.(string); ok {
			return id
		}
	}
	return ""
}

// GetAccountID extracts account ID from Gin context
func GetAccountID(c *gin.Context) string {
	if accountID, exists := c.Get("account_id"); exists {
		if id, ok := accountID.(string); ok {
			return id
		}
	}
	return ""
}

// GetDBPool extracts database pool from context
func GetDBPool(c *gin.Context) (*pgxpool.Pool, bool) {
	pool, exists := c.Get("db_pool")
	if !exists {
		return nil, false
	}

	dbPool, ok := pool.(*pgxpool.Pool)
	return dbPool, ok
}

// GetTransaction extracts current transaction from context
// Returns the transaction if one is active, or nil if not in transaction
func GetTransaction(c *gin.Context) (interface {
	QueryRow(ctx context.Context, sql string, args ...interface{}) interface{}
	Exec(ctx context.Context, sql string, args ...interface{}) (interface{}, error)
}, bool) {
	tx, exists := c.Get("db_tx")
	if !exists {
		return nil, false
	}

	// Type assertion for pgx.Tx (simplified - adjust based on actual pgx version)
	if dbTx, ok := tx.(interface {
		QueryRow(ctx context.Context, sql string, args ...interface{}) interface{}
		Exec(ctx context.Context, sql string, args ...interface{}) (interface{}, error)
	}); ok {
		return dbTx, true
	}

	return nil, false
}

// GetTx returns the pgx.Tx for use in queries
// This is the preferred method for new code
func GetTx(c *gin.Context) (pgx.Tx, bool) {
	tx, exists := c.Get("db_tx")
	if !exists {
		return nil, false
	}

	dbTx, ok := tx.(pgx.Tx)
	return dbTx, ok
}

// RequireTenant creates a middleware that ensures tenant context is present
// Use this for endpoints that absolutely require tenant isolation
func RequireTenant() gin.HandlerFunc {
	return func(c *gin.Context) {
		pharmacyID := GetPharmacyID(c)
		if pharmacyID == "" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "tenant_required",
				"message": "This endpoint requires tenant context",
				"code":    "TENANT_CONTEXT_MISSING",
			})
			return
		}
		c.Next()
	}
}

// SystemAdminBypass allows system administrators to bypass tenant restrictions
// Use with extreme caution - only for platform-level operations
func SystemAdminBypass() gin.HandlerFunc {
	return func(c *gin.Context) {
		role := c.GetString("role")
		if role == "service_role" {
			// System admin - set bypass flag (use carefully in queries)
			c.Set("bypass_rls", true)
		}
		c.Next()
	}
}
