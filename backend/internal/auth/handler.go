package auth

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Handler struct {
	service *Service
	mailer  *mailer
}

func NewHandler(db *pgxpool.Pool, cfg Config) *Handler {
	return &Handler{service: NewService(db, cfg), mailer: newMailer(cfg)}
}

// Middleware authenticates requests with the same opaque session service used
// by the auth endpoints. Keeping this adapter on Handler prevents other
// packages from reaching into the service implementation.
func (h *Handler) Middleware(realm AuthRealm) gin.HandlerFunc {
	return h.service.Middleware(realm)
}

type loginRequest struct {
	Email       string `json:"email" binding:"required,email"`
	Password    string `json:"password" binding:"required"`
	AccountType string `json:"account_type"`
	CompanyID   string `json:"company_id"`
	PharmacyID  string `json:"pharmacy_id"`
}

type passwordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword     string `json:"new_password" binding:"required"`
}

type verificationRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code" binding:"required"`
}

type forgotPasswordRequest struct {
	Email       string `json:"email" binding:"required,email"`
	AccountType string `json:"account_type"`
}

type registerRequest struct {
	CompanyName  string `json:"company_name" binding:"required,min=2,max=255"`
	CompanyEmail string `json:"company_email" binding:"required,email"`
	FirstName    string `json:"first_name" binding:"required,min=1,max=100"`
	LastName     string `json:"last_name" binding:"required,min=1,max=100"`
	Email        string `json:"email" binding:"required,email"`
	Password     string `json:"password" binding:"required"`
}

func (h *Handler) RegisterRoutes(group *gin.RouterGroup) {
	authGroup := group.Group("/auth")
	authGroup.POST("/register", h.register)

	platform := authGroup.Group("/platform")
	platform.POST("/login", h.loginPlatform)
	platform.POST("/refresh", CSRF(PlatformRealm), h.refreshPlatform)
	platform.POST("/logout", CSRF(PlatformRealm), h.logoutPlatform)
	platform.GET("/me", h.service.Middleware(PlatformRealm), h.me)
	platform.POST("/logout-all", h.service.Middleware(PlatformRealm), CSRF(PlatformRealm), h.logoutAllPlatform)
	platform.POST("/change-password", h.service.Middleware(PlatformRealm), CSRF(PlatformRealm), h.changePassword)
	platform.PATCH("/locale", h.service.Middleware(PlatformRealm), CSRF(PlatformRealm), h.updateLocale)

	pharmacy := authGroup.Group("/pharmacy")
	pharmacy.POST("/login", h.loginPharmacy)
	pharmacy.POST("/refresh", CSRF(PharmacyRealm), h.refreshPharmacy)
	pharmacy.POST("/logout", CSRF(PharmacyRealm), h.logoutPharmacy)
	pharmacy.GET("/me", h.service.Middleware(PharmacyRealm), h.me)
	pharmacy.POST("/logout-all", h.service.Middleware(PharmacyRealm), CSRF(PharmacyRealm), h.logoutAllPharmacy)
	pharmacy.POST("/change-password", h.service.Middleware(PharmacyRealm), CSRF(PharmacyRealm), h.changePassword)
	pharmacy.PATCH("/locale", h.service.Middleware(PharmacyRealm), CSRF(PharmacyRealm), h.updateLocale)

	authGroup.POST("/forgot-password", h.forgotPassword)
	authGroup.POST("/reset-password", h.resetPassword)
	authGroup.POST("/verify-email", h.verifyEmail)
	authGroup.POST("/resend-verification", h.resendVerification)
}

func (h *Handler) register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil || !validPassword(req.Password) {
		writeError(c, http.StatusBadRequest, "weak_password", passwordPolicyMessage)
		return
	}
	principal, err := h.service.RegisterCompany(
		c.Request.Context(), req.CompanyName, req.CompanyEmail,
		req.FirstName, req.LastName, req.Email, req.Password,
	)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "duplicate") ||
			strings.Contains(strings.ToLower(err.Error()), "unique") {
			log.Printf("company registration conflict: %v", err)
			writeError(c, http.StatusConflict, "account_exists", "An account with these details already exists")
			return
		}
		log.Printf("company registration failed: %v", err)
		writeError(c, http.StatusInternalServerError, "registration_failed", "Could not create account")
		return
	}
	emailSent, err := h.sendVerificationEmail(c.Request.Context(), principal)
	if err != nil {
		log.Printf("registration verification email failed: %v", err)
	}
	c.JSON(http.StatusCreated, gin.H{
		"user":                        userPayload(principal),
		"message":                     "Account created. Please verify your email before signing in.",
		"email_verification_sent":     emailSent,
		"email_verification_required": true,
	})
}

func (h *Handler) loginPlatform(c *gin.Context) {
	h.loginForRealm(c, PlatformRealm)
}

func (h *Handler) loginPharmacy(c *gin.Context) {
	h.loginForRealm(c, PharmacyRealm)
}

func (h *Handler) loginForRealm(c *gin.Context, realm AuthRealm) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		writeError(c, http.StatusBadRequest, "validation_error", "Email and password are required")
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.AccountType == "company" {
		req.AccountType = CompanyUserPrincipal
	}
	if req.AccountType == "pharmacy" {
		req.AccountType = EmployeePrincipal
	}

	principal, tokens, err := h.service.Login(
		c.Request.Context(), req.Email, req.Password, req.AccountType,
		firstNonEmpty(req.CompanyID, req.PharmacyID), realm,
		RequestMeta{IPAddress: c.ClientIP(), UserAgent: c.GetHeader("User-Agent")},
	)
	if err != nil {
		switch {
		case errors.Is(err, ErrAccountLocked):
			writeError(c, http.StatusLocked, "account_locked", "Account temporarily locked")
		case errors.Is(err, ErrLoginRateLimited):
			c.Header("Retry-After", "900")
			writeError(c, http.StatusTooManyRequests, "login_rate_limited", "Too many login attempts. Try again shortly.")
		case errors.Is(err, ErrAccountInactive):
			writeError(c, http.StatusForbidden, "account_inactive", "Account is inactive")
		case errors.Is(err, ErrEmailNotVerified):
			if principal != nil {
				if _, sendErr := h.sendVerificationEmail(c.Request.Context(), principal); sendErr != nil {
					log.Printf("login verification email failed for principal type %s: %v", principal.Type, sendErr)
				}
			}
			writeError(c, http.StatusForbidden, "email_not_verified", "يرجى تأكيد بريدك الإلكتروني قبل تسجيل الدخول")
		default:
			writeError(c, http.StatusUnauthorized, "invalid_credentials", "Invalid email or password")
		}
		return
	}
	if err := h.setAuthCookies(c, tokens, realm); err != nil {
		log.Printf("auth cookie setup failed: %v", err)
		writeError(c, http.StatusInternalServerError, "session_error", "Could not create a secure session")
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"data": map[string]interface{}{
			"user":       userPayload(principal),
			"expires_in": int64(h.service.cfg.AccessTTL.Seconds()),
		},
		"user":    userPayload(principal),
		"message": "Login successful",
	})
}

func (h *Handler) refreshPlatform(c *gin.Context) {
	h.refreshForRealm(c, PlatformRealm)
}

func (h *Handler) refreshPharmacy(c *gin.Context) {
	h.refreshForRealm(c, PharmacyRealm)
}

func (h *Handler) refreshForRealm(c *gin.Context, realm AuthRealm) {
	refreshToken := refreshTokenFromRequest(realm, c)
	if refreshToken == "" {
		writeError(c, http.StatusUnauthorized, "refresh_required", "Refresh session required")
		return
	}
	principal, tokens, err := h.service.Refresh(c.Request.Context(), refreshToken, realm, RequestMeta{
		IPAddress: c.ClientIP(), UserAgent: c.GetHeader("User-Agent"),
	})
	if err != nil {
		h.clearAuthCookies(c, realm)
		writeError(c, http.StatusUnauthorized, "invalid_refresh_session", "Refresh session expired or invalid")
		return
	}
	if err := h.setAuthCookies(c, tokens, realm); err != nil {
		writeError(c, http.StatusInternalServerError, "session_error", "Could not rotate session")
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"user":       userPayload(principal),
		"expires_in": int64(h.service.cfg.AccessTTL.Seconds()),
	})
}

func (h *Handler) logoutPlatform(c *gin.Context) {
	h.logoutForRealm(c, PlatformRealm)
}

func (h *Handler) logoutPharmacy(c *gin.Context) {
	h.logoutForRealm(c, PharmacyRealm)
}

func (h *Handler) logoutForRealm(c *gin.Context, realm AuthRealm) {
	_ = h.service.RevokeTokens(c.Request.Context(), accessTokenFromRequest(realm, c), refreshTokenFromRequest(realm, c))
	h.clearAuthCookies(c, realm)
	c.JSON(http.StatusOK, gin.H{"message": "Logged out"})
}

func (h *Handler) me(c *gin.Context) {
	principal, ok := PrincipalFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "authentication_required", "Authentication required")
		return
	}
	c.JSON(http.StatusOK, gin.H{"user": userPayload(principal)})
}

func (h *Handler) logoutAllPlatform(c *gin.Context) {
	h.logoutAllForRealm(c, PlatformRealm)
}

func (h *Handler) logoutAllPharmacy(c *gin.Context) {
	h.logoutAllForRealm(c, PharmacyRealm)
}

func (h *Handler) logoutAllForRealm(c *gin.Context, realm AuthRealm) {
	principal, _ := PrincipalFromContext(c)
	if err := h.service.RevokeAllInRealm(c.Request.Context(), principal, realm); err != nil {
		writeError(c, http.StatusInternalServerError, "logout_failed", "Could not revoke sessions")
		return
	}
	h.clearAuthCookies(c, realm)
	c.JSON(http.StatusOK, gin.H{"message": "All sessions revoked"})
}

func (h *Handler) changePassword(c *gin.Context) {
	principal, _ := PrincipalFromContext(c)
	var req passwordRequest
	if err := c.ShouldBindJSON(&req); err != nil || !validPassword(req.NewPassword) {
		writeError(c, http.StatusBadRequest, "weak_password", passwordPolicyMessage)
		return
	}
	if err := h.service.ChangePassword(c.Request.Context(), principal, req.CurrentPassword, req.NewPassword); err != nil {
		if errors.Is(err, ErrInvalidCredentials) {
			writeError(c, http.StatusUnauthorized, "invalid_password", "Current password is incorrect")
			return
		}
		writeError(c, http.StatusInternalServerError, "password_update_failed", "Could not update password")
		return
	}
	realm := AuthRealm(c.GetString("auth_realm"))
	h.clearAuthCookies(c, realm)
	c.JSON(http.StatusOK, gin.H{"message": "Password changed. Please sign in again."})
}

func (h *Handler) forgotPassword(c *gin.Context) {
	var req forgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		writeError(c, http.StatusBadRequest, "validation_error", "A valid email is required")
		return
	}
	principal, err := h.service.FindPrincipal(c.Request.Context(), req.Email, normalizePrincipalType(req.AccountType), "")
	if err == nil {
		token, tokenErr := h.service.CreateEmailToken(c.Request.Context(), principal, ResetPasswordPurpose)
		if tokenErr != nil {
			writeError(c, http.StatusInternalServerError, "reset_failed", "Could not create reset request")
			return
		}
		if err := h.mailer.resetEmail(c.Request.Context(), principal.Email, token); err != nil {
			log.Printf("password reset email failed for principal type %s: %v", principal.Type, err)
			writeError(c, http.StatusServiceUnavailable, "email_service_unavailable", "Email service is not configured")
			return
		}
	} else if !errors.Is(err, pgx.ErrNoRows) {
		log.Printf("password reset lookup failed: %v", err)
	}
	// Do not reveal whether an email exists.
	c.JSON(http.StatusOK, gin.H{"message": "If an account exists, a reset link will be sent"})
}

func (h *Handler) resendVerification(c *gin.Context) {
	var req forgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		writeError(c, http.StatusBadRequest, "validation_error", "A valid email is required")
		return
	}
	principal, err := h.service.FindPrincipal(c.Request.Context(), req.Email, normalizePrincipalType(req.AccountType), "")
	if err == nil && !principal.EmailVerified {
		sent, sendErr := h.sendVerificationEmail(c.Request.Context(), principal)
		if sendErr != nil {
			log.Printf("verification email failed for principal type %s: %v", principal.Type, sendErr)
			writeError(c, http.StatusServiceUnavailable, "email_delivery_failed", "تعذر إرسال رمز التحقق الآن. تحقق من إعداد البريد وحاول مرة أخرى")
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"message": "If the account needs verification, a code will be sent",
			"sent":    sent,
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "If the account needs verification, a code will be sent", "sent": false})
}

func (h *Handler) sendVerificationEmail(ctx context.Context, principal *Principal) (bool, error) {
	code, sent, err := h.service.CreateEmailTokenIfDue(ctx, principal, VerifyEmailPurpose)
	if err != nil || !sent {
		return sent, err
	}
	if err := h.mailer.verificationEmail(ctx, principal.Email, code); err != nil {
		if invalidateErr := h.service.InvalidateEmailToken(ctx, principal, VerifyEmailPurpose); invalidateErr != nil {
			log.Printf("verification token cleanup failed for principal type %s: %v", principal.Type, invalidateErr)
		}
		return false, err
	}
	return true, nil
}

func (h *Handler) resetPassword(c *gin.Context) {
	var req struct {
		Token       string `json:"token" binding:"required"`
		NewPassword string `json:"new_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || !validPassword(req.NewPassword) {
		writeError(c, http.StatusBadRequest, "weak_password", passwordPolicyMessage)
		return
	}
	principal, err := h.service.ConsumeEmailToken(c.Request.Context(), req.Token, ResetPasswordPurpose)
	if err != nil {
		writeError(c, http.StatusBadRequest, "invalid_token", "Invalid or expired reset token")
		return
	}
	if err := h.service.UpdatePasswordFromReset(c.Request.Context(), principal, req.NewPassword); err != nil {
		writeError(c, http.StatusInternalServerError, "password_update_failed", "Could not update password")
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Password reset successfully"})
}

func (h *Handler) verifyEmail(c *gin.Context) {
	var req verificationRequest
	if err := c.ShouldBindJSON(&req); err != nil || !isVerificationCode(req.Code) {
		writeError(c, http.StatusBadRequest, "validation_error", "A valid 6-digit verification code is required")
		return
	}
	principal, err := h.service.ConsumeEmailVerificationCode(c.Request.Context(), req.Email, req.Code)
	if err != nil {
		writeError(c, http.StatusBadRequest, "invalid_code", "Invalid or expired verification code")
		return
	}
	if err := h.service.MarkEmailVerified(c.Request.Context(), principal); err != nil {
		writeError(c, http.StatusInternalServerError, "verification_failed", "Could not verify email")
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Email verified successfully"})
}

func isVerificationCode(code string) bool {
	if len(code) != 6 {
		return false
	}
	for _, digit := range code {
		if digit < '0' || digit > '9' {
			return false
		}
	}
	return true
}

func (h *Handler) setAuthCookies(c *gin.Context, tokens *SessionTokens, realm AuthRealm) error {
	csrf, err := newCSRFToken()
	if err != nil {
		return err
	}
	secure := h.service.cfg.CookieSecure
	sameSite := http.SameSiteLaxMode
	if secure {
		sameSite = http.SameSiteNoneMode
	}
	setCookie := func(name, value string, maxAge int, httpOnly bool, path string) {
		http.SetCookie(c.Writer, &http.Cookie{
			Name: name, Value: value, Path: path, Domain: h.service.cfg.CookieDomain,
			MaxAge: maxAge, Secure: secure, HttpOnly: httpOnly, SameSite: sameSite,
		})
	}
	setCookie(accessCookieName(realm), tokens.AccessToken, int(h.service.cfg.AccessTTL.Seconds()), true, "/")
	setCookie(refreshCookieName(realm), tokens.RefreshToken, int(h.service.cfg.RefreshTTL.Seconds()), true, "/api/v1/auth")
	setCookie(csrfCookieName(realm), csrf, int(h.service.cfg.RefreshTTL.Seconds()), false, "/")
	return nil
}

func (h *Handler) clearAuthCookies(c *gin.Context, realm AuthRealm) {
	secure := h.service.cfg.CookieSecure
	sameSite := http.SameSiteLaxMode
	if secure {
		sameSite = http.SameSiteNoneMode
	}
	for _, cookie := range []struct {
		name, path string
	}{{accessCookieName(realm), "/"}, {refreshCookieName(realm), "/api/v1/auth"}, {csrfCookieName(realm), "/"}} {
		http.SetCookie(c.Writer, &http.Cookie{
			Name: cookie.name, Value: "", Path: cookie.path, Domain: h.service.cfg.CookieDomain,
			MaxAge: -1, Secure: secure, HttpOnly: cookie.name != csrfCookieName(realm), SameSite: sameSite,
		})
	}
}

func userPayload(p *Principal) map[string]interface{} {
	payload := map[string]interface{}{
		"id": p.ID, "email": p.Email, "first_name": p.FirstName, "last_name": p.LastName,
		"display_name": p.DisplayName, "role": p.Role, "account_type": p.Type,
		"is_active": p.IsActive, "email_verified": p.EmailVerified,
		"locale": p.Locale,
	}
	if p.CompanyID != "" {
		payload["company_id"] = p.CompanyID
	}
	if p.PharmacyID != "" {
		payload["pharmacy_id"] = p.PharmacyID
	}
	if p.BranchID != "" {
		payload["branch_id"] = p.BranchID
	}
	return payload
}

const passwordPolicyMessage = "Password must be at least 10 characters and include uppercase, lowercase, number, and special character"

func validPassword(password string) bool {
	if len(password) < 10 || len(password) > 128 {
		return false
	}
	var upper, lower, digit, special bool
	for _, char := range password {
		switch {
		case char >= 'A' && char <= 'Z':
			upper = true
		case char >= 'a' && char <= 'z':
			lower = true
		case char >= '0' && char <= '9':
			digit = true
		default:
			special = true
		}
	}
	return upper && lower && digit && special
}

func normalizePrincipalType(value string) string {
	switch value {
	case "company", CompanyUserPrincipal:
		return CompanyUserPrincipal
	case "pharmacy", EmployeePrincipal:
		return EmployeePrincipal
	default:
		return ""
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func writeError(c *gin.Context, status int, code, message string) {
	c.JSON(status, gin.H{"error": code, "code": strings.ToUpper(code), "message": message})
}

// allowedUILocales mirrors the frontend catalog allowlist and the CHECK
// constraints added by migration 21. Keep the three lists in sync.
var allowedUILocales = map[string]bool{
	"ar": true, "en": true, "fr": true, "es": true,
	"tr": true, "zh": true, "hi": true, "ur": true,
}

type localeRequest struct {
	Locale string `json:"locale" binding:"required"`
}

// updateLocale persists the caller's UI language preference. It is
// self-service by design: any authenticated principal may change its own
// locale, no pharmacy permission involved.
func (h *Handler) updateLocale(c *gin.Context) {
	principal, ok := PrincipalFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "authentication_required", "Authentication required")
		return
	}
	var req localeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		writeError(c, http.StatusBadRequest, "validation_error", "A locale value is required")
		return
	}
	req.Locale = strings.ToLower(strings.TrimSpace(req.Locale))
	if !allowedUILocales[req.Locale] {
		writeError(c, http.StatusBadRequest, "unsupported_locale", "Unsupported locale")
		return
	}
	if err := h.service.SetLocale(c.Request.Context(), principal, req.Locale); err != nil {
		log.Printf("locale update failed for principal type %s: %v", principal.Type, err)
		writeError(c, http.StatusInternalServerError, "locale_update_failed", "Could not update language preference")
		return
	}
	c.JSON(http.StatusOK, gin.H{"locale": req.Locale})
}
