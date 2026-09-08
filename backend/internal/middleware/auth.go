// Package middleware contains shared request-context helpers for the Go API.
// Authentication itself is implemented by internal/auth and backed by the
// application's PostgreSQL database.
package middleware

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// SessionClaims is the small subset of session data used by authorization
// middleware. Tokens are opaque and are never parsed in this package.
type SessionClaims struct {
	UserID            string
	Email             string
	Role              string
	PrincipalType     string
	CompanyID         string
	PharmacyID        string
	BranchID          string
	PermissionVersion int
}

func GetUserID(c *gin.Context) string {
	return contextString(c, "user_id")
}

func GetEmail(c *gin.Context) string {
	return contextString(c, "email")
}

func GetSessionID(c *gin.Context) string {
	return contextString(c, "session_id")
}

func GetPermissionVersion(c *gin.Context) int {
	if value, exists := c.Get("permission_version"); exists {
		if version, ok := value.(int); ok {
			return version
		}
	}
	return 0
}

func GetSessionClaims(c *gin.Context) (SessionClaims, bool) {
	userID := GetUserID(c)
	if userID == "" {
		return SessionClaims{}, false
	}
	return SessionClaims{
		UserID: GetUserID(c), Email: GetEmail(c), Role: contextString(c, "role"),
		PrincipalType: contextString(c, "principal_type"),
		CompanyID:     contextString(c, "company_id"), PharmacyID: contextString(c, "pharmacy_id"),
		BranchID: contextString(c, "branch_id"), PermissionVersion: GetPermissionVersion(c),
	}, true
}

func IsAuthenticated(c *gin.Context) bool {
	return GetUserID(c) != ""
}

// extractToken is retained for the legacy company authorization middleware.
// Browser authentication uses internal/auth and opaque cookies.
func extractToken(c *gin.Context, tokenLookup string) (string, error) {
	parts := strings.SplitN(tokenLookup, ":", 2)
	if len(parts) != 2 {
		return "", errors.New("invalid token lookup format")
	}
	switch parts[0] {
	case "header":
		value := c.GetHeader(parts[1])
		if value == "" {
			return "", errors.New("missing authorization header")
		}
		return strings.TrimPrefix(value, "Bearer "), nil
	case "query":
		value := c.Query(parts[1])
		if value == "" {
			return "", fmt.Errorf("missing query parameter: %s", parts[1])
		}
		return value, nil
	case "cookie":
		value, err := c.Cookie(parts[1])
		if err != nil || value == "" {
			return "", fmt.Errorf("missing cookie: %s", parts[1])
		}
		return value, nil
	default:
		return "", fmt.Errorf("unsupported token source: %s", parts[0])
	}
}

func generateRequestID() string {
	return fmt.Sprintf("%d-%d", time.Now().UnixNano(), time.Now().UnixMicro())
}

func contextString(c *gin.Context, key string) string {
	value, exists := c.Get(key)
	if !exists {
		return ""
	}
	result, _ := value.(string)
	return result
}
