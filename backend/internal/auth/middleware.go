package auth

import (
	"crypto/rand"
	"encoding/base64"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

const (
	CSRFHeaderName = "X-CSRF-Token"
)

type contextKey string

const principalContextKey contextKey = "auth_principal"

// Middleware authenticates requests using the short-lived opaque access cookie.
// Authorization Bearer is retained for server-to-server clients, not browsers.
func (s *Service) Middleware(realm AuthRealm) gin.HandlerFunc {
	return func(c *gin.Context) {
		token := accessTokenFromRequest(realm, c)
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "authentication_required", "message": "Authentication required",
			})
			return
		}
		principal, err := s.Authenticate(c.Request.Context(), token, realm)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "invalid_session", "message": "Session expired or invalid",
			})
			return
		}
		setPrincipal(c, principal)
		c.Set("auth_realm", string(realm))
		c.Next()
	}
}

// RequirePharmacyPrincipal allows an authenticated company owner or pharmacy
// employee to access the pharmacy attached to the current principal. The
// pharmacy scope is always derived from the session, never from the request.
func RequirePharmacyPrincipal() gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := PrincipalFromContext(c)
		if !ok ||
			(principal.Type != EmployeePrincipal && principal.Type != CompanyUserPrincipal) ||
			principal.PharmacyID == "" ||
			principal.Role == "super_admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "pharmacy_account_required",
				"message": "An active pharmacy account is required",
			})
			return
		}
		c.Next()
	}
}

// RequireEmployeePrincipal restricts sensitive pharmacy operations to employee
// identities. Company users can read the pharmacy dashboard through
// RequirePharmacyPrincipal, but they do not automatically gain employee-only
// mutation privileges.
func RequireEmployeePrincipal() gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := PrincipalFromContext(c)
		if !ok || principal.Type != EmployeePrincipal || principal.PharmacyID == "" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "pharmacy_employee_required",
				"message": "An active pharmacy employee account is required",
			})
			return
		}
		c.Next()
	}
}

// RequirePharmacyMutationPrincipal allows pharmacy employees and company
// administrators/managers to perform pharmacy mutations. Company viewers are
// intentionally kept read-only.
func RequirePharmacyMutationPrincipal() gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := PrincipalFromContext(c)
		if !ok || principal.PharmacyID == "" || principal.ID == "" ||
			(principal.Type != EmployeePrincipal &&
				(principal.Type != CompanyUserPrincipal ||
					(principal.Role != "company_admin" && principal.Role != "company_manager"))) {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error":   "pharmacy_mutation_account_required",
				"message": "حساب مدير أو موظف صيدلية نشط مطلوب لتنفيذ هذه العملية",
			})
			return
		}
		c.Next()
	}
}

// CSRF protects cookie-authenticated state-changing requests with a
// double-submit token. GET, HEAD and OPTIONS remain safe without the header.
func CSRF(realm AuthRealm) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.Method == http.MethodGet || c.Request.Method == http.MethodHead || c.Request.Method == http.MethodOptions {
			c.Next()
			return
		}
		cookie, err := c.Cookie(csrfCookieName(realm))
		header := c.GetHeader(CSRFHeaderName)
		if err != nil || cookie == "" || header == "" || cookie != header {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "csrf_failed", "message": "CSRF validation failed",
			})
			return
		}
		c.Next()
	}
}

func setPrincipal(c *gin.Context, principal *Principal) {
	c.Set(string(principalContextKey), principal)
	c.Set("user_id", principal.ID)
	c.Set("auth_user_id", principal.ID)
	c.Set("email", principal.Email)
	c.Set("role", principal.Role)
	c.Set("principal_type", principal.Type)
	c.Set("company_id", principal.CompanyID)
	c.Set("pharmacy_id", principal.PharmacyID)
	c.Set("branch_id", principal.BranchID)
	c.Set("permission_version", principal.PermissionVersion)
}

func PrincipalFromContext(c *gin.Context) (*Principal, bool) {
	value, exists := c.Get(string(principalContextKey))
	if !exists {
		return nil, false
	}
	principal, ok := value.(*Principal)
	return principal, ok
}

func accessTokenFromRequest(realm AuthRealm, c *gin.Context) string {
	if value, err := c.Cookie(accessCookieName(realm)); err == nil && value != "" {
		return value
	}
	header := strings.TrimSpace(c.GetHeader("Authorization"))
	if strings.HasPrefix(header, "Bearer ") {
		return strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
	}
	return ""
}

func refreshTokenFromRequest(realm AuthRealm, c *gin.Context) string {
	value, _ := c.Cookie(refreshCookieName(realm))
	return value
}

func accessCookieName(realm AuthRealm) string {
	if realm == PlatformRealm {
		return "platform_access"
	}
	return "pharmacy_access"
}

func refreshCookieName(realm AuthRealm) string {
	if realm == PlatformRealm {
		return "platform_refresh"
	}
	return "pharmacy_refresh"
}

func csrfCookieName(realm AuthRealm) string {
	if realm == PlatformRealm {
		return "platform_csrf"
	}
	return "pharmacy_csrf"
}

func newCSRFToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}
