// Package middleware - Company Authentication (Custom Auth, NOT Supabase)
// Phase 2 - Holding Company SaaS Platform
// This file handles JWT-based authentication for company users with custom password hashing
package middleware

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// ============================================
// Company JWT Claims
// ============================================

// CompanyClaims represents JWT claims for company user authentication
type CompanyClaims struct {
	UserID            string `json:"user_id"`
	Email             string `json:"email"`
	CompanyID         string `json:"company_id"`
	Role              string `json:"role"`               // super_admin, company_admin, etc.
	PermissionVersion int    `json:"permission_version"` // For cache invalidation
	IsSuperAdmin      bool   `json:"is_super_admin"`

	jwt.RegisteredClaims
}

// ============================================
// Company Auth Configuration
// ============================================

// CompanyAuthConfig holds configuration for company authentication
type CompanyAuthConfig struct {
	JWTSecret        string        // Secret key for signing JWTs
	JWTExpiry        time.Duration // How long tokens are valid (default: 24h)
	BcryptCost       int           // Bcrypt cost factor (default: 12)
	MaxLoginAttempts int           // Max failed attempts before lockout (default: 5)
	LockoutDuration  time.Duration // How long to lock account (default: 30min)
	TokenLookup      string        // Where to find token (default: "header:Authorization")
	TimeSkew         time.Duration // Allowed clock skew (default: 30s)
}

// DefaultCompanyAuthConfig returns default company auth configuration
func DefaultCompanyAuthConfig(jwtSecret string) *CompanyAuthConfig {
	return &CompanyAuthConfig{
		JWTSecret:        jwtSecret,
		JWTExpiry:        24 * time.Hour,
		BcryptCost:       12,
		MaxLoginAttempts: 5,
		LockoutDuration:  30 * time.Minute,
		TokenLookup:      "header:Authorization",
		TimeSkew:         30 * time.Second,
	}
}

// ============================================
// Context Keys for Company Auth
// ============================================

type companyContextKey string

const (
	CompanyUserIDKey    companyContextKey = "company_user_id"
	CompanyUserEmailKey companyContextKey = "company_user_email"
	CompanyIDKey        companyContextKey = "company_id"
	CompanyRoleKey      companyContextKey = "company_role"
	CompanyIsSuperAdmin companyContextKey = "company_is_super_admin"
	CompanyPermVersion  companyContextKey = "company_permission_version"
	CompanyClaimsKey    companyContextKey = "company_jwt_claims"
)

// ============================================
// Password Hashing Utilities
// ============================================

// HashPassword hashes a password using bcrypt
func HashPassword(password string, cost int) (string, error) {
	if cost == 0 {
		cost = 12 // default cost
	}
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), cost)
	if err != nil {
		return "", fmt.Errorf("failed to hash password: %w", err)
	}
	return string(bytes), nil
}

// CheckPassword compares a plaintext password with a hashed password
func CheckPassword(password, hash string) error {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	if err != nil {
		return errors.New("invalid email or password")
	}
	return nil
}

// GenerateSecureToken generates a cryptographically secure random token
func GenerateSecureToken(length int) (string, error) {
	bytes := make([]byte, length)
	_, err := rand.Read(bytes)
	if err != nil {
		return "", fmt.Errorf("failed to generate token: %w", err)
	}
	return hex.EncodeToString(bytes), nil
}

// ============================================
// Company Authentication Middleware
// ============================================

// CompanyAuth creates middleware that validates company user JWT tokens
// This is the main authentication guard for company-level API endpoints
func CompanyAuth(config *CompanyAuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString, err := extractToken(c, config.TokenLookup)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "company_auth_required",
				"message": "Company authentication required",
				"code":    "COMPANY_MISSING_TOKEN",
			})
			return
		}

		claims, err := validateCompanyToken(tokenString, config)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "invalid_company_token",
				"message": err.Error(),
				"code":    "COMPANY_INVALID_TOKEN",
			})
			return
		}

		// Set company user context
		setCompanyUserContext(c, claims)

		c.Next()
	}
}

// OptionalCompanyAuth creates middleware that validates company token if present but doesn't require it
func OptionalCompanyAuth(config *CompanyAuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString, err := extractToken(c, config.TokenLookup)
		if err != nil {
			c.Set("company_authenticated", false)
			c.Next()
			return
		}

		claims, err := validateCompanyToken(tokenString, config)
		if err != nil {
			c.Set("company_authenticated", false)
			c.Next()
			return
		}

		setCompanyUserContext(c, claims)
		c.Set("company_authenticated", true)
		c.Next()
	}
}

// SuperAdminOnly creates middleware that only allows super admins
func SuperAdminOnly(config *CompanyAuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		// First authenticate
		tokenString, err := extractToken(c, config.TokenLookup)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "authentication_required",
				"message": "Super admin authentication required",
				"code":    "SUPER_ADMIN_AUTH_REQUIRED",
			})
			return
		}

		claims, err := validateCompanyToken(tokenString, config)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "invalid_token",
				"message": err.Error(),
				"code":    "INVALID_TOKEN",
			})
			return
		}

		// Check if super admin
		if !claims.IsSuperAdmin {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "forbidden",
				"message": "This action requires super admin privileges",
				"code":    "SUPER_ADMIN_REQUIRED",
			})
			return
		}

		setCompanyUserContext(c, claims)
		c.Next()
	}
}

// ============================================
// Token Validation
// ============================================

// validateCompanyToken parses and validates a company JWT token
func validateCompanyToken(tokenString string, config *CompanyAuthConfig) (*CompanyClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &CompanyClaims{}, func(token *jwt.Token) (interface{}, error) {
		// Validate signing method (we use HS256)
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return []byte(config.JWTSecret), nil
	})

	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, errors.New("token has expired")
		}
		if errors.Is(err, jwt.ErrTokenNotValidYet) {
			return nil, errors.New("token is not valid yet")
		}
		return nil, fmt.Errorf("failed to parse token: %w", err)
	}

	if !token.Valid {
		return nil, errors.New("token is invalid")
	}

	claims, ok := token.Claims.(*CompanyClaims)
	if !ok {
		return nil, errors.New("failed to extract token claims")
	}

	// Validate required claims
	if claims.UserID == "" {
		return nil, errors.New("missing user ID in token")
	}
	if claims.CompanyID == "" {
		return nil, errors.New("missing company ID in token")
	}

	// Validate expiry with time skew
	if claims.ExpiresAt != nil && time.Now().After(claims.ExpiresAt.Time.Add(config.TimeSkew)) {
		return nil, errors.New("token has expired")
	}

	// Validate issued-at time
	if claims.IssuedAt != nil && claims.IssuedAt.Time.After(time.Now().Add(config.TimeSkew)) {
		return nil, errors.New("token issued in the future")
	}

	return claims, nil
}

// GenerateCompanyToken generates a new JWT token for a company user
func GenerateCompanyToken(userID, email, companyID, role string, permissionVersion int, isSuperAdmin bool, config *CompanyAuthConfig) (string, error) {
	now := time.Now()
	claims := CompanyClaims{
		UserID:            userID,
		Email:             email,
		CompanyID:         companyID,
		Role:              role,
		PermissionVersion: permissionVersion,
		IsSuperAdmin:      isSuperAdmin,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "pharmacy-os-company-auth",
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(config.JWTExpiry)),
			ID:        generateRequestID(),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signedToken, err := token.SignedString([]byte(config.JWTSecret))
	if err != nil {
		return "", fmt.Errorf("failed to sign token: %w", err)
	}

	return signedToken, nil
}

// ValidateCompanyToken exposes token validation to integration tests and
// trusted internal callers without duplicating JWT parsing logic.
func ValidateCompanyToken(tokenString string, config *CompanyAuthConfig) (*CompanyClaims, error) {
	return validateCompanyToken(tokenString, config)
}

// ============================================
// Context Setting Helpers
// ============================================

// setCompanyUserContext sets the authenticated company user's info in Gin context
func setCompanyUserContext(c *gin.Context, claims *CompanyClaims) {
	// Set in Gin context for easy access
	c.Set("company_user_id", claims.UserID)
	c.Set("company_user_email", claims.Email)
	c.Set("company_id", claims.CompanyID)
	c.Set("company_role", claims.Role)
	c.Set("company_is_super_admin", claims.IsSuperAdmin)
	c.Set("company_permission_version", claims.PermissionVersion)
	c.Set("company_jwt_claims", claims)
	c.Set("company_authenticated", true)

	// Set in context for Go handlers
	ctx := context.WithValue(c.Request.Context(), CompanyUserIDKey, claims.UserID)
	ctx = context.WithValue(ctx, CompanyUserEmailKey, claims.Email)
	ctx = context.WithValue(ctx, CompanyIDKey, claims.CompanyID)
	ctx = context.WithValue(ctx, CompanyRoleKey, claims.Role)
	ctx = context.WithValue(ctx, CompanyIsSuperAdmin, claims.IsSuperAdmin)
	ctx = context.WithValue(ctx, CompanyPermVersion, claims.PermissionVersion)
	ctx = context.WithValue(ctx, CompanyClaimsKey, claims)

	c.Request = c.Request.WithContext(ctx)
}

// ============================================
// Getter Functions for Company Context
// ============================================

// GetCompanyUserID extracts company user ID from context
func GetCompanyUserID(c *gin.Context) string {
	if id, exists := c.Get("company_user_id"); exists {
		if str, ok := id.(string); ok {
			return str
		}
	}
	return ""
}

// GetCompanyUserEmail extracts company user email from context
func GetCompanyUserEmail(c *gin.Context) string {
	if email, exists := c.Get("company_user_email"); exists {
		if str, ok := email.(string); ok {
			return str
		}
	}
	return ""
}

// GetCompanyID extracts company ID from context
func GetCompanyID(c *gin.Context) string {
	if id, exists := c.Get("company_id"); exists {
		if str, ok := id.(string); ok {
			return str
		}
	}
	return ""
}

// GetCompanyRole extracts company user role from context
func GetCompanyRole(c *gin.Context) string {
	if role, exists := c.Get("company_role"); exists {
		if str, ok := role.(string); ok {
			return str
		}
	}
	return ""
}

// IsCompanySuperAdmin checks if current user is a super admin
func IsCompanySuperAdmin(c *gin.Context) bool {
	if isAdmin, exists := c.Get("company_is_super_admin"); exists {
		if b, ok := isAdmin.(bool); ok {
			return b
		}
	}
	return false
}

// GetCompanyPermissionVersion extracts permission version from context
func GetCompanyPermissionVersion(c *gin.Context) int {
	if ver, exists := c.Get("company_permission_version"); exists {
		if v, ok := ver.(int); ok {
			return v
		}
	}
	return 0
}

// GetCompanyJWTClaims extracts full JWT claims from context
func GetCompanyJWTClaims(c *gin.Context) (*CompanyClaims, bool) {
	claims, exists := c.Get("company_jwt_claims")
	if !exists {
		return nil, false
	}

	jwtClaims, ok := claims.(*CompanyClaims)
	return jwtClaims, ok
}

// IsCompanyAuthenticated checks if request has valid company authentication
func IsCompanyAuthenticated(c *gin.Context) bool {
	if auth, exists := c.Get("company_authenticated"); exists {
		if b, ok := auth.(bool); ok {
			return b
		}
	}
	return false
}

// RequireCompanyAuth is a helper that checks company auth and aborts if not authenticated
func RequireCompanyAuth(c *gin.Context) error {
	if !IsCompanyAuthenticated(c) {
		return errors.New("company authentication required")
	}
	if GetCompanyUserID(c) == "" {
		return errors.New("valid company user not found in context")
	}
	return nil
}

// ============================================
// Account Lockout Helpers
// ============================================

// IsAccountLocked checks if an account should be locked due to too many failed attempts
func IsAccountLocked(loginAttempts int, lockedUntil *time.Time, maxAttempts int, lockoutDuration time.Duration) bool {
	if loginAttempts >= maxAttempts {
		if lockedUntil != nil {
			if time.Now().Before(*lockedUntil) {
				return true // Still locked
			}
			// Lockout period expired, can try again
			return false
		}
		// Just reached max attempts, should lock
		return true
	}
	return false
}

// CalculateLockoutTime calculates when lockout should end
func CalculateLockoutTime(lockoutDuration time.Duration) time.Time {
	return time.Now().Add(lockoutDuration)
}

// ============================================
// Response Types
// ============================================

// CompanyAuthResponse represents login response for company user
type CompanyAuthResponse struct {
	User        interface{} `json:"user"`
	AccessToken string      `json:"access_token"`
	TokenType   string      `json:"token_type"`
	ExpiresIn   int64       `json:"expires_in"` // seconds
	Company     interface{} `json:"company"`
}

// CompanyUserInfo represents basic company user info in responses
type CompanyUserInfo struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	FirstName   string `json:"first_name"`
	LastName    string `json:"last_name"`
	DisplayName string `json:"display_name,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
	Role        string `json:"role"`
	CompanyID   string `json:"company_id"`
	CompanyName string `json:"company_name"`
}

// TokenRefreshResponse represents token refresh response
type TokenRefreshResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int64  `json:"expires_in"`
}

// extractToken extracts token from request (reused from auth.go logic)
// This is a copy to avoid circular dependencies or we could refactor
func extractCompanyToken(c *gin.Context, tokenLookup string) (string, error) {
	parts := strings.SplitN(tokenLookup, ":", 2)
	if len(parts) != 2 {
		return "", errors.New("invalid token lookup format")
	}

	source := parts[0]
	name := parts[1]

	switch source {
	case "header":
		authHeader := c.GetHeader(name)
		if authHeader == "" {
			return "", errors.New("missing authorization header")
		}
		if strings.HasPrefix(authHeader, "Bearer ") {
			token := strings.TrimPrefix(authHeader, "Bearer ")
			if token == "" {
				return "", errors.New("empty bearer token")
			}
			return token, nil
		}
		return authHeader, nil

	case "query":
		token := c.Query(name)
		if token == "" {
			return "", fmt.Errorf("missing query parameter: %s", name)
		}
		return token, nil

	case "cookie":
		token, err := c.Cookie(name)
		if err != nil {
			return "", fmt.Errorf("missing cookie: %s", name)
		}
		return token, nil

	default:
		return "", fmt.Errorf("unsupported token source: %s", source)
	}
}
