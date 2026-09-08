// Package middleware - Company User Permissions (Holding Company Level)
// Phase 2 - Multi-Tenant SaaS Architecture
// This file implements the dynamic permission system for company users
//
// Same pattern as employee permissions but for company level:
// - Permissions stored in company_user_permissions table (SOURCE OF TRUTH)
// - Reuses existing permissions table (company-specific permission keys)
// - Each permission check queries database (with caching)
// - Version-based cache invalidation
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

// ============================================
// Company Permission Configuration
// ============================================

// CompanyPermissionConfig holds configuration for company permission middleware
type CompanyPermissionConfig struct {
        // CacheTTL defines how long to cache company permission checks (default: 2 minutes)
        CacheTTL time.Duration
        
        // CacheMaxSize maximum number of cached company permissions (default: 5000)
        CacheMaxSize int
        
        // EnforceStrictMode if true, denies access when in doubt
        EnforceStrictMode bool
}

// DefaultCompanyPermissionConfig returns default company permission configuration
func DefaultCompanyPermissionConfig() *CompanyPermissionConfig {
        return &CompanyPermissionConfig{
                CacheTTL:         2 * time.Minute,
                CacheMaxSize:     5000,
                EnforceStrictMode: true,
        }
}

// ============================================
// Company Permission Cache
// ============================================

// CompanyPermissionCache is a simple in-memory cache for company permission lookups
// Separate from employee permission cache to avoid conflicts and allow different TTLs
type CompanyPermissionCache struct {
        mu       sync.RWMutex
        entries map[string]*companyCacheEntry
        maxSize int
        ttl     time.Duration
}

type companyCacheEntry struct {
        value      bool
        expiration time.Time
        version    int // Company user permission version at time of caching
}

// NewCompanyPermissionCache creates a new company permission cache
func NewCompanyPermissionCache(maxSize int, ttl time.Duration) *CompanyPermissionCache {
        return &CompanyPermissionCache{
                entries: make(map[string]*companyCacheEntry),
                maxSize: maxSize,
                ttl:     ttl,
        }
}

// Get retrieves a cached company permission value
// Returns (value, found, expired)
func (cpc *CompanyPermissionCache) get(key string, currentVersion int) (bool, bool, bool) {
        cpc.mu.RLock()
        defer cpc.mu.RUnlock()
        
        entry, exists := cpc.entries[key]
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

// Set stores a value in the company permission cache
func (cpc *CompanyPermissionCache) set(key string, value bool, version int) {
        cpc.mu.Lock()
        defer cpc.mu.Unlock()
        
        // Evict oldest entries if at capacity
        if len(cpc.entries) >= cpc.maxSize {
                cpc.evictOldest()
        }
        
        cpc.entries[key] = &companyCacheEntry{
                value:      value,
                expiration: time.Now().Add(cpc.ttl),
                version:    version,
        }
}

// evictOldest removes the oldest cache entry
func (cpc *CompanyPermissionCache) evictOldest() {
        var oldestKey string
        var oldestTime time.Time
        
        for key, entry := range cpc.entries {
                if oldestKey == "" || entry.expiration.Before(oldestTime) {
                        oldestKey = key
                        oldestTime = entry.expiration
                }
        }
        
        if oldestKey != "" {
                delete(cpc.entries, oldestKey)
        }
}

// Clear removes all company permission cache entries
func (cpc *CompanyPermissionCache) Clear() {
        cpc.mu.Lock()
        defer cpc.mu.Unlock()
        
        cpc.entries = make(map[string]*companyCacheEntry)
}

// Global company permission cache instance
var defaultCompanyPermissionCache = NewCompanyPermissionCache(5000, 2*time.Minute)

// ============================================
// Company Permission Middleware Functions
// ============================================

// RequireCompanyPermission creates middleware that checks if current company user has specified permission
// Usage:
//
//      r.GET("/api/v1/companies/:id", companyAuth, RequireCompanyPermission("companies.view"), getCompany)
//      r.POST("/api/v1/companies/:id/users", companyAuth, RequireCompanyPermission("company_users.create"), createUser)
//
// The middleware:
// 1. Extracts company_user_id from context (set by CompanyTenantContext middleware)
// 2. Checks cache first (for performance)
// 3. Queries database if not cached
// 4. Caches the result for future requests
// 5. Returns 403 Forbidden if permission not granted
func RequireCompanyPermission(permissionKey string) gin.HandlerFunc {
        return RequireCompanyPermissionWithConfig(permissionKey, DefaultCompanyPermissionConfig())
}

// RequireCompanyPermissionWithConfig creates company permission middleware with custom configuration
func RequireCompanyPermissionWithConfig(permissionKey string, config *CompanyPermissionConfig) gin.HandlerFunc {
        // Validate permission key format
        if err := validateCompanyPermissionKey(permissionKey); err != nil && config.EnforceStrictMode {
                return func(c *gin.Context) {
                        c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
                                "error":   "invalid_company_permission_config",
                                "message": "Company permission key format is invalid",
                                "code":    "INVALID_COMPANY_PERMISSION_KEY",
                        })
                }
        }
        
        cache := NewCompanyPermissionCache(config.CacheMaxSize, config.CacheTTL)
        
        return func(c *gin.Context) {
                companyUserID := GetCompanyUserID(c)
                if companyUserID == "" {
                        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                                "error":   "company_auth_required",
                                "message": "Company user must be authenticated to check permissions",
                                "code":    "COMPANY_USER_ID_REQUIRED",
                        })
                        return
                }
                
                // Get permission version from JWT claims (for cache invalidation)
                permissionVersion := GetCompanyPermissionVersion(c)
                
                // Build cache key
                cacheKey := buildCompanyCacheKey(companyUserID, permissionKey)
                
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
                                "error":              "company_permission_denied",
                                "message":            fmt.Sprintf("You do not have company permission: %s", permissionKey),
                                "code":               "COMPANY_PERMISSION_DENIED",
                                "required_permission": permissionKey,
                        })
                        return
                }
                
                // Cache miss or expired - query database
                hasPerm, err := checkCompanyPermissionFromDB(c, companyUserID, permissionKey)
                if err != nil {
                        // Database error handling based on strict mode
                        if config.EnforceStrictMode {
                                c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
                                        "error":   "company_permission_check_failed",
                                        "message": "Failed to verify company permission",
                                        "code":    "COMPANY_PERMISSION_CHECK_ERROR",
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
                        "error":              "company_permission_denied",
                        "message":            fmt.Sprintf("You do not have company permission: %s", permissionKey),
                        "code":               "COMPANY_PERMISSION_DENIED",
                        "required_permission": permissionKey,
                })
        }
}

// RequireAnyCompanyPermission creates middleware that allows access if user has ANY of the specified company permissions
func RequireAnyCompanyPermission(permissionKeys ...string) gin.HandlerFunc {
        return func(c *gin.Context) {
                companyUserID := GetCompanyUserID(c)
                if companyUserID == "" {
                        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                                "error":   "company_auth_required",
                                "message": "Company user must be authenticated",
                                "code":    "COMPANY_AUTH_REQUIRED",
                        })
                        return
                }
                
                for _, permKey := range permissionKeys {
                        hasPerm, _ := checkCompanyPermissionFromDB(c, companyUserID, permKey)
                        if hasPerm {
                                c.Next()
                                return
                        }
                }
                
                // None of the permissions were granted
                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                        "error":                "company_permission_denied",
                        "message":              "You do not have any of the required company permissions",
                        "code":                 "NO_REQUIRED_COMPANY_PERMISSIONS",
                        "required_permissions":  permissionKeys,
                })
        }
}

// RequireAllCompanyPermissions creates middleware that allows access only if user has ALL specified company permissions
func RequireAllCompanyPermissions(permissionKeys ...string) gin.HandlerFunc {
        return func(c *gin.Context) {
                companyUserID := GetCompanyUserID(c)
                if companyUserID == "" {
                        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                                "error":   "company_auth_required",
                                "message": "Company user must be authenticated",
                                "code":    "COMPANY_AUTH_REQUIRED",
                        })
                        return
                }
                
                for _, permKey := range permissionKeys {
                        hasPerm, _ := checkCompanyPermissionFromDB(c, companyUserID, permKey)
                        if !hasPerm {
                                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                                        "error":                "company_permission_denied",
                                        "message":              fmt.Sprintf("Missing required company permission: %s", permKey),
                                        "code":                 "MISSING_COMPANY_PERMISSION",
                                        "missing_permission":    permKey,
                                        "required_permissions":  permissionKeys,
                                })
                                return
                        }
                }
                
                // All permissions granted
                c.Next()
        }
}

// ============================================
// Database Query Functions
// ============================================

// checkCompanyPermissionFromDB queries database to check if a company user has a specific permission
// Uses company_user_permissions table as SOURCE OF TRUTH
func checkCompanyPermissionFromDB(c *gin.Context, companyUserID string, permissionKey string) (bool, error) {
        ctx := c.Request.Context()

        // Try to get transaction from context (preferred - maintains RLS context)
        _, hasTx := GetCompanyTransaction(c)
        
        const query = `
                SELECT EXISTS (
                        SELECT 1 FROM company_user_permissions cup
                        JOIN permissions p ON cup.permission_id = p.id
                        WHERE cup.company_user_id = $1 
                          AND p.key = $2 
                          AND cup.is_active = true
                )
        `
        
        var hasPermission bool
        var err error
        
        if hasTx {
                // Use existing transaction (maintains RLS context)
                dbTx, _ := GetCompanyTx(c)
                row := dbTx.QueryRow(ctx, query, companyUserID, permissionKey)
                err = row.Scan(&hasPermission)
        } else {
                // Fallback: use DB pool directly
                pool, hasPool := GetCompanyDBPool(c)
                if !hasPool {
                        return false, fmt.Errorf("no database connection available")
                }
                
                row := pool.QueryRow(ctx, query, companyUserID, permissionKey)
                err = row.Scan(&hasPermission)
        }
        
        if err != nil {
                return false, fmt.Errorf("failed to check company permission: %w", err)
        }
        
        return hasPermission, nil
}

// GetCompanyUserPermissions returns all active permissions for the current company user
// Useful for frontend permission UI or conditional rendering
func GetCompanyUserPermissions(c *gin.Context) ([]string, error) {
        companyUserID := GetCompanyUserID(c)
        if companyUserID == "" {
                return nil, fmt.Errorf("not authenticated as company user")
        }
        
        ctx := c.Request.Context()
        _, hasTx := GetCompanyTransaction(c)
        
        const query = `
                SELECT p.key 
                FROM company_user_permissions cup
                JOIN permissions p ON cup.permission_id = p.id
                WHERE cup.company_user_id = $1 
                  AND cup.is_active = true
                ORDER BY p.module, p.key
        `
        
        var rows pgx.Rows
        var err error
        
        if hasTx {
                dbTx, _ := GetCompanyTx(c)
                rows, err = dbTx.Query(ctx, query, companyUserID)
        } else {
                pool, hasPool := GetCompanyDBPool(c)
                if !hasPool {
                        return nil, fmt.Errorf("no database connection available")
                }
                rows, err = pool.Query(ctx, query, companyUserID)
        }
        
        if err != nil {
                return nil, fmt.Errorf("failed to query company permissions: %w", err)
        }
        defer rows.Close()
        
        var permissions []string
        for rows.Next() {
                var permKey string
                if err := rows.Scan(&permKey); err != nil {
                        return nil, fmt.Errorf("failed to scan company permission: %w", err)
                }
                permissions = append(permissions, permKey)
        }
        
        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating company permissions: %w", err)
        }
        
        return permissions, nil
}

// ============================================
// Helper Functions
// ============================================

// validateCompanyPermissionKey checks if a permission key follows expected format
func validateCompanyPermissionKey(key string) error {
        if key == "" {
                return fmt.Errorf("company permission key cannot be empty")
        }
        
        parts := strings.Split(key, ".")
        if len(parts) != 2 {
                return fmt.Errorf("company permission key must be in format 'module.action', got: %s", key)
        }
        
        module := parts[0]
        action := parts[1]
        
        if module == "" || action == "" {
                return fmt.Errorf("module and action cannot be empty in company permission key: %s", key)
        }
        
        // Validate characters (lowercase alphanumeric and underscore only)
        for _, ch := range module + "." + action {
                if !((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '.') {
                        return fmt.Errorf("invalid character in company permission key '%s'. Only lowercase letters, numbers, underscores, and dots allowed", key)
                }
        }
        
        return nil
}

// buildCompanyCacheKey creates unique cache key for company user+permission combination
func buildCompanyCacheKey(companyUserID, permissionKey string) string {
        return fmt.Sprintf("comp:%s:%s", companyUserID, permissionKey)
}

// InvalidateCompanyUserCache clears cached permissions for a specific company user
// Call this after granting/revoking company user permissions
func InvalidateCompanyUserCache(companyUserID string) {
        // Version-based invalidation handles most cases
        // For explicit cache clearing, would need Redis or similar for pattern deletion
        // This is a no-op with our simple in-memory cache
}

// ============================================
// Response Types
// ============================================

// CompanyPermissionResponse represents API response for company permission endpoints
type CompanyPermissionResponse struct {
        CompanyUserID string   `json:"company_user_id"`
        Permissions   []string `json:"permissions"`
        GrantedAt     time.Time `json:"granted_at,omitempty"`
        Version       int      `json:"permission_version"`
}

// CheckCompanyPermissionResponse represents response for single company permission check
type CheckCompanyPermissionResponse struct {
        CompanyUserID      string `json:"company_user_id"`
        PermissionKey      string `json:"permission_key"`
        HasPermission      bool   `json:"has_permission"`
        Cached             bool   `json:"cached"`
        PermissionVersion  int    `json:"permission_version"`
}
