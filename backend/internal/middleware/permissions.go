// Package middleware provides HTTP middleware for permission-based authorization
// This file implements the dynamic permission system where:
// - Permissions are stored in employee_permissions table (SOURCE OF TRUTH)
// - Roles are just templates, not the authorization source
// - Each permission check queries the database (with caching)
//
// Permission keys follow the format: module.action
// Examples: employees.create, inventory.adjust, reports.view
package middleware

import (
        "fmt"
        "net/http"
        "strings"
        "sync"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
)

// PermissionConfig holds configuration for permission middleware
type PermissionConfig struct {
        // CacheTTL defines how long to cache permission checks (default: 1 minute)
        CacheTTL time.Duration
        
        // CacheMaxSize maximum number of cached permissions (default: 10000)
        CacheMaxSize int
        
        // EnforceStrictMode if true, denies access when in doubt
        EnforceStrictMode bool
}

// DefaultPermissionConfig returns default permission configuration
func DefaultPermissionConfig() *PermissionConfig {
        return &PermissionConfig{
                CacheTTL:         1 * time.Minute,
                CacheMaxSize:     10000,
                EnforceStrictMode: true,
        }
}

// PermissionCache is a simple in-memory cache for permission lookups
// In production, consider using Redis or similar for distributed caching
type PermissionCache struct {
        mu       sync.RWMutex
        entries map[string]*cacheEntry
        maxSize int
        ttl     time.Duration
}

type cacheEntry struct {
        value      bool
        expiration time.Time
        version    int // Permission version at time of caching
}

// NewPermissionCache creates a new permission cache
func NewPermissionCache(maxSize int, ttl time.Duration) *PermissionCache {
        return &PermissionCache{
                entries: make(map[string]*cacheEntry),
                maxSize: maxSize,
                ttl:     ttl,
        }
}

// Get retrieves a cached permission value
// Returns (value, found, expired)
func (pc *PermissionCache) get(key string, currentVersion int) (bool, bool, bool) {
        pc.mu.RLock()
        defer pc.mu.RUnlock()
        
        entry, exists := pc.entries[key]
        if !exists {
                return false, false, false
        }
        
        // Check if cache entry is expired
        if time.Now().After(entry.expiration) {
                return entry.value, true, true // Found but expired
        }
        
        // Check if permission version has changed (invalidation)
        if entry.version != currentVersion {
                return entry.value, true, true // Version mismatch, treat as expired
        }
        
        return entry.value, true, false // Valid cache hit
}

// Set stores a value in the cache
func (pc *PermissionCache) set(key string, value bool, version int) {
        pc.mu.Lock()
        defer pc.mu.Unlock()
        
        // Evict oldest entries if at capacity
        if len(pc.entries) >= pc.maxSize {
                pc.evictOldest()
        }
        
        pc.entries[key] = &cacheEntry{
                value:      value,
                expiration: time.Now().Add(pc.ttl),
                version:    version,
        }
}

// evictOldest removes the oldest cache entry (simple LRU-like behavior)
func (pc *PermissionCache) evictOldest() {
        var oldestKey string
        var oldestTime time.Time
        
        for key, entry := range pc.entries {
                if oldestKey == "" || entry.expiration.Before(oldestTime) {
                        oldestKey = key
                        oldestTime = entry.expiration
                }
        }
        
        if oldestKey != "" {
                delete(pc.entries, oldestKey)
        }
}

// Clear removes all cache entries (useful for testing or admin operations)
func (pc *PermissionCache) Clear() {
        pc.mu.Lock()
        defer pc.mu.Unlock()
        
        pc.entries = make(map[string]*cacheEntry)
}

// Global permission cache instance (can be replaced with dependency injection)
var defaultPermissionCache = NewPermissionCache(10000, 1*time.Minute)

// RequirePermission creates middleware that checks if the current user has the specified permission
// Usage:
//
//      r.GET("/api/employees", authMiddleware, RequirePermission("employees.view"), listEmployees)
//      r.POST("/api/employees", authMiddleware, RequirePermission("employees.create"), createEmployee)
//
// The middleware:
// 1. Extracts employee_id from context (set by TenantContext middleware)
// 2. Checks cache first (for performance)
// 3. Queries database if not cached
// 4. Caches the result for future requests
// 5. Returns 403 Forbidden if permission not granted
func RequirePermission(permissionKey string) gin.HandlerFunc {
        return RequirePermissionWithConfig(permissionKey, DefaultPermissionConfig())
}

// RequirePermissionWithConfig creates permission middleware with custom configuration
func RequirePermissionWithConfig(permissionKey string, config *PermissionConfig) gin.HandlerFunc {
        // Validate permission key format
        if err := validatePermissionKey(permissionKey); err != nil && config.EnforceStrictMode {
                return func(c *gin.Context) {
                        c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
                                "error":   "invalid_permission_config",
                                "message": "Permission key format is invalid",
                                "code":    "INVALID_PERMISSION_KEY",
                        })
                }
        }
        
        cache := NewPermissionCache(config.CacheMaxSize, config.CacheTTL)
        
        return func(c *gin.Context) {
                employeeID := GetEmployeeID(c)
                if employeeID == "" {
                        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                                "error":   "authentication_required",
                                "message": "User must be authenticated to check permissions",
                                "code":    "EMPLOYEE_ID_REQUIRED",
                        })
                        return
                }
                
                // Get permission version from JWT claims (for cache invalidation)
                permissionVersion := getPermissionVersion(c)
                
                // Build cache key
                cacheKey := buildCacheKey(employeeID, permissionKey)
                
                // Check cache first
                hasPermission, found, expired := cache.get(cacheKey, permissionVersion)
                
                if found && !expired {
                        // Cache hit - use cached value
                        if hasPermission {
                                c.Next()
                                return
                        }
                        
                        // Permission denied (cached)
                        c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                                "error":   "permission_denied",
                                "message": fmt.Sprintf("You do not have permission: %s", permissionKey),
                                "code":    "PERMISSION_DENIED",
                                "required_permission": permissionKey,
                        })
                        return
                }
                
                // Cache miss or expired - query database
                hasPerm, err := checkPermissionFromDB(c, employeeID, permissionKey)
                if err != nil {
                        // Database error handling based on strict mode
                        if config.EnforceStrictMode {
                                c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
                                        "error":   "permission_check_failed",
                                        "message": "Failed to verify permission",
                                        "code":    "PERMISSION_CHECK_ERROR",
                                })
                                return
                        }
                        // Non-strict mode: allow access if we can't verify (less secure)
                        c.Next()
                        return
                }
                
                // Cache the result
                cache.set(cacheKey, hasPerm, permissionVersion)
                
                // Make decision based on database result
                if hasPerm {
                        c.Next()
                        return
                }
                
                // Permission denied
                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                        "error":   "permission_denied",
                        "message": fmt.Sprintf("You do not have permission: %s", permissionKey),
                        "code":    "PERMISSION_DENIED",
                        "required_permission": permissionKey,
                })
        }
}

// RequireAnyPermission creates middleware that allows access if user has ANY of the specified permissions
// Useful for endpoints that can be accessed via multiple permission paths
func RequireAnyPermission(permissionKeys ...string) gin.HandlerFunc {
        return func(c *gin.Context) {
                employeeID := GetEmployeeID(c)
                if employeeID == "" {
                        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                                "error":   "authentication_required",
                                "message": "User must be authenticated",
                                "code":    "AUTH_REQUIRED",
                        })
                        return
                }
                
                for _, permKey := range permissionKeys {
                        hasPerm, _ := checkPermissionFromDB(c, employeeID, permKey)
                        if hasPerm {
                                c.Next()
                                return
                        }
                }
                
                // None of the permissions were granted
                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                        "error":   "permission_denied",
                        "message": "You do not have any of the required permissions",
                        "code":    "NO_REQUIRED_PERMISSIONS",
                        "required_permissions": permissionKeys,
                })
        }
}

// RequireAllPermissions creates middleware that allows access only if user has ALL specified permissions
// Useful for highly sensitive operations requiring multiple permissions
func RequireAllPermissions(permissionKeys ...string) gin.HandlerFunc {
        return func(c *gin.Context) {
                employeeID := GetEmployeeID(c)
                if employeeID == "" {
                        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                                "error":   "authentication_required",
                                "message": "User must be authenticated",
                                "code":    "AUTH_REQUIRED",
                        })
                        return
                }
                
                for _, permKey := range permissionKeys {
                        hasPerm, _ := checkPermissionFromDB(c, employeeID, permKey)
                        if !hasPerm {
                                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                                        "error":   "permission_denied",
                                        "message": fmt.Sprintf("Missing required permission: %s", permKey),
                                        "code":    "MISSING_PERMISSION",
                                        "missing_permission": permKey,
                                        "required_permissions": permissionKeys,
                                })
                                return
                        }
                }
                
                // All permissions granted
                c.Next()
        }
}

// checkPermissionFromDB queries the database to check if an employee has a specific permission
// This uses the employee_permissions table as the SOURCE OF TRUTH
func checkPermissionFromDB(c *gin.Context, employeeID string, permissionKey string) (bool, error) {
        ctx := c.Request.Context()

        // Try to get transaction from context (preferred - maintains RLS context)
        _, hasTx := GetTransaction(c)
        
        const query = `
                SELECT EXISTS (
                        SELECT 1 FROM employee_permissions ep
                        JOIN permissions p ON ep.permission_id = p.id
                        WHERE ep.employee_id = $1 
                          AND p.key = $2 
                          AND ep.is_active = true
                )
        `
        
        var hasPermission bool
        var err error
        
        if hasTx {
                // Use existing transaction (maintains RLS context)
                dbTx, _ := GetTx(c)
                row := dbTx.QueryRow(ctx, query, employeeID, permissionKey)
                err = row.Scan(&hasPermission)
        } else {
                // Fallback: use DB pool directly (shouldn't normally happen)
                pool, hasPool := GetDBPool(c)
                if !hasPool {
                        return false, fmt.Errorf("no database connection available")
                }
                
                row := pool.QueryRow(ctx, query, employeeID, permissionKey)
                err = row.Scan(&hasPermission)
        }
        
        if err != nil {
                return false, fmt.Errorf("failed to check permission: %w", err)
        }
        
        return hasPermission, nil
}

// GetUserPermissions returns all active permissions for the current user
// Useful for frontend permission UI or conditional rendering
func GetUserPermissions(c *gin.Context) ([]string, error) {
        employeeID := GetEmployeeID(c)
        if employeeID == "" {
                return nil, fmt.Errorf("not authenticated")
        }
        
        ctx := c.Request.Context()
        _, hasTx := GetTransaction(c)
        
        const query = `
                SELECT p.key 
                FROM employee_permissions ep
                JOIN permissions p ON ep.permission_id = p.id
                WHERE ep.employee_id = $1 
                  AND ep.is_active = true
                ORDER BY p.module, p.key
        `
        
        var rows pgx.Rows
        var err error

        if hasTx {
                dbTx, _ := GetTx(c)
                rows, err = dbTx.Query(ctx, query, employeeID)
        } else {
                pool, hasPool := GetDBPool(c)
                if !hasPool {
                        return nil, fmt.Errorf("no database connection available")
                }
                rows, err = pool.Query(ctx, query, employeeID)
        }
        
        if err != nil {
                return nil, fmt.Errorf("failed to query permissions: %w", err)
        }
        defer rows.Close()
        
        var permissions []string
        for rows.Next() {
                var permKey string
                if err := rows.Scan(&permKey); err != nil {
                        return nil, fmt.Errorf("failed to scan permission: %w", err)
                }
                permissions = append(permissions, permKey)
        }
        
        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating permissions: %w", err)
        }
        
        return permissions, nil
}

// Helper functions

// validatePermissionKey checks if a permission key follows the expected format
func validatePermissionKey(key string) error {
        if key == "" {
                return fmt.Errorf("permission key cannot be empty")
        }
        
        parts := strings.Split(key, ".")
        if len(parts) != 2 {
                return fmt.Errorf("permission key must be in format 'module.action', got: %s", key)
        }
        
        module := parts[0]
        action := parts[1]
        
        if module == "" || action == "" {
                return fmt.Errorf("module and action cannot be empty in permission key: %s", key)
        }
        
        // Validate characters (lowercase alphanumeric and underscore only)
        for _, ch := range module + "." + action {
                if !((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '.') {
                        return fmt.Errorf("invalid character in permission key '%s'. Only lowercase letters, numbers, underscores, and dots allowed", key)
                }
        }
        
        return nil
}

// buildCacheKey creates a unique cache key for employee+permission combination
func buildCacheKey(employeeID, permissionKey string) string {
        return fmt.Sprintf("%s:%s", employeeID, permissionKey)
}

// getPermissionVersion extracts permission version from the authenticated session
// Used for cache invalidation when permissions change
func getPermissionVersion(c *gin.Context) int {
        return GetPermissionVersion(c)
}

// InvalidateUserCache clears cached permissions for a specific user
// Call this after granting/revoking permissions
func InvalidateUserCache(employeeID string) {
        // Since we don't know all possible permission keys, clear doesn't help much
        // Instead, the permission_version mechanism handles invalidation
        // But we can provide this for explicit cache clearing if needed
        // In a real implementation with Redis, you'd delete keys by pattern: "emp:{employeeID}:*"
        
        // For now, this is a no-op since our simple cache doesn't support pattern deletion
        // The version-based invalidation will handle it on next check
}

// PermissionResponse represents API response for permission-related endpoints
type PermissionResponse struct {
        EmployeeID  string   `json:"employee_id"`
        Permissions []string `json:"permissions"`
        GrantedAt   time.Time `json:"granted_at,omitempty"`
        Version     int      `json:"permission_version"`
}

// CheckPermissionResponse represents response for single permission check
type CheckPermissionResponse struct {
        EmployeeID       string `json:"employee_id"`
        PermissionKey    string `json:"permission_key"`
        HasPermission    bool   `json:"has_permission"`
        Cached           bool   `json:"cached"`
        PermissionVersion int    `json:"permission_version"`
}
