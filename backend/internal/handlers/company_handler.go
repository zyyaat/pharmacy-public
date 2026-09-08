// Package handlers - Holding Company / SaaS Platform Handlers
// Phase 2 - Multi-Tenant Architecture
// This file handles HTTP requests for company management (CRUD + Auth)
package handlers

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/pharmacy-os/backend/internal/middleware"
	"github.com/pharmacy-os/backend/internal/models"
	"github.com/pharmacy-os/backend/internal/repository"
)

// ============================================
// Company Handler
// ============================================

// CompanyHandler handles company-related HTTP requests
type CompanyHandler struct {
	companyRepo *repository.CompanyRepository
	userRepo    *repository.CompanyUserRepository
	permRepo    *repository.CompanyUserPermissionRepository
	authConfig  *middleware.CompanyAuthConfig
}

// NewCompanyHandler creates a new CompanyHandler
func NewCompanyHandler(
	companyRepo *repository.CompanyRepository,
	userRepo *repository.CompanyUserRepository,
	permRepo *repository.CompanyUserPermissionRepository,
	authConfig *middleware.CompanyAuthConfig,
) *CompanyHandler {
	return &CompanyHandler{
		companyRepo: companyRepo,
		userRepo:    userRepo,
		permRepo:    permRepo,
		authConfig:  authConfig,
	}
}

// ============================================
// Company CRUD Endpoints
// ============================================

// CreateCompany creates a new holding company (SaaS customer)
// POST /api/v1/companies
func (h *CompanyHandler) CreateCompany(c *gin.Context) {
	var req models.CompanyCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "validation_error",
			"message": err.Error(),
			"code":    "INVALID_REQUEST",
		})
		return
	}

	// Check if email already exists
	exists, err := h.companyRepo.CheckEmailExists(c.Request.Context(), req.Email, "")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "database_error",
			"message": "Failed to validate company email",
			"code":    "DB_ERROR",
		})
		return
	}
	if exists {
		c.JSON(http.StatusConflict, gin.H{
			"error":   "duplicate_email",
			"message": "A company with this email already exists",
			"code":    "DUPLICATE_EMAIL",
		})
		return
	}

	// Set defaults
	if req.Country == "" {
		req.Country = "EG"
	}
	if req.Timezone == "" {
		req.Timezone = "Africa/Cairo"
	}
	if req.Locale == "" {
		req.Locale = "ar-EG"
	}
	if req.DefaultCurrency == "" {
		req.DefaultCurrency = "EGP"
	}
	if req.MaxAccounts == nil {
		defaultMax := 1
		req.MaxAccounts = &defaultMax
	}
	if req.MaxUsersPerAccount == nil {
		defaultMaxUsers := 10
		req.MaxUsersPerAccount = &defaultMaxUsers
	}

	company, err := h.companyRepo.Create(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "creation_failed",
			"message": "Failed to create company",
			"code":    "COMPANY_CREATE_ERROR",
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"data":    company,
		"message": "Company created successfully",
	})
}

// GetCompany returns a company by ID
// GET /api/v1/companies/:id
func (h *CompanyHandler) GetCompany(c *gin.Context) {
	id := c.Param("id")
	if !companyAccessAllowed(c, id) {
		writeCompanyForbidden(c)
		return
	}

	company, err := h.companyRepo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "not_found",
			"message": "Company not found",
			"code":    "COMPANY_NOT_FOUND",
		})
		return
	}

	// Get summary with counts
	companyWithSummary, err := h.companyRepo.GetSummary(c.Request.Context(), id)
	if err != nil {
		// Fallback to basic company info if summary fails
		c.JSON(http.StatusOK, gin.H{
			"data": company,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": companyWithSummary,
	})
}

// UpdateCompany updates an existing company
// PUT /api/v1/companies/:id
func (h *CompanyHandler) UpdateCompany(c *gin.Context) {
	id := c.Param("id")
	if !companyAccessAllowed(c, id) {
		writeCompanyForbidden(c)
		return
	}

	var req models.CompanyUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "validation_error",
			"message": err.Error(),
			"code":    "INVALID_REQUEST",
		})
		return
	}

	company, err := h.companyRepo.Update(c.Request.Context(), id, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "update_failed",
			"message": "Failed to update company",
			"code":    "COMPANY_UPDATE_ERROR",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":    company,
		"message": "Company updated successfully",
	})
}

// ListCompanies returns paginated list of companies
// GET /api/v1/companies
func (h *CompanyHandler) ListCompanies(c *gin.Context) {
	page := 1
	pageSize := 20
	var status *string

	// Parse query parameters
	if p := c.Query("page"); p != "" {
		if parsed, err := parseIntParam(p); err == nil && parsed > 0 {
			page = parsed
		}
	}
	if ps := c.Query("page_size"); ps != "" {
		if parsed, err := parseIntParam(ps); err == nil && parsed > 0 && parsed <= 100 {
			pageSize = parsed
		}
	}
	if s := c.Query("status"); s != "" {
		status = &s
	}

	if !middleware.IsCompanySuperAdmin(c) {
		id := middleware.GetCompanyID(c)
		company, err := h.companyRepo.GetByID(c.Request.Context(), id)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found", "message": "Company not found"})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"data":       []interface{}{company},
			"pagination": gin.H{"total": 1, "page": 1, "page_size": 1, "total_pages": 1},
		})
		return
	}

	companies, total, err := h.companyRepo.List(c.Request.Context(), page, pageSize, status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "query_failed",
			"message": "Failed to retrieve companies",
			"code":    "COMPANY_LIST_ERROR",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": companies,
		"pagination": gin.H{
			"total":       total,
			"page":        page,
			"page_size":   pageSize,
			"total_pages": (total + int64(pageSize) - 1) / int64(pageSize),
		},
	})
}

// DeleteCompany soft deletes a company
// DELETE /api/v1/companies/:id
func (h *CompanyHandler) DeleteCompany(c *gin.Context) {
	id := c.Param("id")
	if !companyAccessAllowed(c, id) {
		writeCompanyForbidden(c)
		return
	}

	err := h.companyRepo.SoftDelete(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "delete_failed",
			"message": err.Error(),
			"code":    "COMPANY_DELETE_ERROR",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Company deleted successfully",
	})
}

// UpdateCompanyStatus updates company status (active/suspended/cancelled)
// PATCH /api/v1/companies/:id/status
func (h *CompanyHandler) UpdateCompanyStatus(c *gin.Context) {
	id := c.Param("id")
	if !companyAccessAllowed(c, id) {
		writeCompanyForbidden(c)
		return
	}

	var req struct {
		Status models.CompanyStatus `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "validation_error",
			"message": "Status is required",
			"code":    "INVALID_REQUEST",
		})
		return
	}

	err := h.companyRepo.UpdateStatus(c.Request.Context(), id, req.Status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "update_failed",
			"message": "Failed to update company status",
			"code":    "STATUS_UPDATE_ERROR",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Company status updated successfully",
	})
}

// GetCompanySummary returns company with account/user counts
// GET /api/v1/companies/:id/summary
func (h *CompanyHandler) GetCompanySummary(c *gin.Context) {
	id := c.Param("id")
	if !companyAccessAllowed(c, id) {
		writeCompanyForbidden(c)
		return
	}

	company, err := h.companyRepo.GetSummary(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "not_found",
			"message": "Company not found",
			"code":    "COMPANY_NOT_FOUND",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": company,
	})
}

// ============================================
// Company Authentication Endpoints
// ============================================

// Login authenticates a company user and returns JWT token
// POST /api/v1/companies/auth/login
func (h *CompanyHandler) Login(c *gin.Context) {
	var req models.CompanyUserLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "validation_error",
			"message": "Email and password are required",
			"code":    "INVALID_REQUEST",
		})
		return
	}

	// Find company by email first (to get company_id)
	company, err := h.companyRepo.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "invalid_credentials",
			"message": "Invalid email or password",
			"code":    "INVALID_CREDENTIALS",
		})
		return
	}

	// Get user with password hash
	user, passwordHash, err := h.userRepo.GetWithPasswordHash(c.Request.Context(), req.Email, company.ID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "invalid_credentials",
			"message": "Invalid email or password",
			"code":    "INVALID_CREDENTIALS",
		})
		return
	}

	// Check if account is locked
	if user.LockedUntil != nil && time.Now().Before(*user.LockedUntil) {
		c.JSON(http.StatusLocked, gin.H{
			"error":        "account_locked",
			"message":      "Account is temporarily locked due to too many failed attempts",
			"code":         "ACCOUNT_LOCKED",
			"locked_until": user.LockedUntil,
		})
		return
	}

	// Check if account is active
	if !user.IsActive {
		c.JSON(http.StatusForbidden, gin.H{
			"error":   "account_inactive",
			"message": "Account is deactivated",
			"code":    "ACCOUNT_INACTIVE",
		})
		return
	}

	// Verify password
	if err := middleware.CheckPassword(req.Password, passwordHash); err != nil {
		// Increment login attempts
		isLocked, lockErr := h.userRepo.IncrementLoginAttempts(
			c.Request.Context(),
			user.ID,
			h.authConfig.MaxLoginAttempts,
			h.authConfig.LockoutDuration,
		)
		if lockErr != nil {
			// Log error but continue
		}

		if isLocked {
			c.JSON(http.StatusLocked, gin.H{
				"error":   "account_locked",
				"message": "Too many failed attempts. Account locked temporarily.",
				"code":    "ACCOUNT_LOCKED",
			})
			return
		}

		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "invalid_credentials",
			"message": "Invalid email or password",
			"code":    "INVALID_CREDENTIALS",
		})
		return
	}

	// Update login info (reset attempts, set last_login)
	if err := h.userRepo.UpdateLoginInfo(c.Request.Context(), user.ID); err != nil {
		// Log error but don't fail login
	}

	// Generate JWT token
	isSuperAdmin := user.Role == models.CompanyRoleSuperAdmin
	token, err := middleware.GenerateCompanyToken(
		user.ID,
		user.Email,
		company.ID,
		string(user.Role),
		user.PermissionVersion,
		isSuperAdmin,
		h.authConfig,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "token_generation_failed",
			"message": "Failed to generate authentication token",
			"code":    "TOKEN_ERROR",
		})
		return
	}

	// Build response
	displayName := ""
	if user.DisplayName != nil {
		displayName = *user.DisplayName
	}
	avatarURL := ""
	if user.AvatarURL != nil {
		avatarURL = *user.AvatarURL
	}

	response := models.CompanyUserLoginResponse{
		User: models.CompanyUser{
			ID:          user.ID,
			Email:       user.Email,
			FirstName:   user.FirstName,
			LastName:    user.LastName,
			DisplayName: &displayName,
			AvatarURL:   &avatarURL,
			Role:        user.Role,
			CompanyID:   company.ID,
		},
		AccessToken: token,
		TokenType:   "Bearer",
		ExpiresIn:   int64(h.authConfig.JWTExpiry.Seconds()),
		Company:     *company,
	}

	c.JSON(http.StatusOK, gin.H{
		"data":    response,
		"message": "Login successful",
	})
}

// Register creates a new company and initial admin user
// POST /api/v1/companies/auth/register
func (h *CompanyHandler) Register(c *gin.Context) {
	var req struct {
		Company models.CompanyCreateRequest     `json:"company" binding:"required"`
		User    models.CompanyUserCreateRequest `json:"user" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "validation_error",
			"message": err.Error(),
			"code":    "INVALID_REQUEST",
		})
		return
	}

	// Set default role for first user as company_admin
	if req.User.Role == "" {
		req.User.Role = models.CompanyRoleAdmin
	}

	// Create company
	company, err := h.companyRepo.Create(c.Request.Context(), &req.Company)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "registration_failed",
			"message": "Failed to create company",
			"code":    "REGISTRATION_ERROR",
		})
		return
	}

	// Hash password
	passwordHash, err := middleware.HashPassword(req.User.Password, h.authConfig.BcryptCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "hash_failed",
			"message": "Failed to process password",
			"code":    "PASSWORD_ERROR",
		})
		return
	}

	// Create admin user
	user, err := h.userRepo.Create(c.Request.Context(), &req.User, company.ID, passwordHash)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "user_creation_failed",
			"message": "Failed to create admin user",
			"code":    "USER_CREATE_ERROR",
		})
		return
	}

	// Grant initial permissions to admin (all company-level permissions)
	initialPerms := []string{
		"companies.view", "companies.update",
		"company_users.view", "company_users.create", "company_users.update",
		"accounts.view", "accounts.create", "accounts.update",
	}

	_, _ = h.permRepo.BatchGrant(c.Request.Context(), user.ID, initialPerms, user.ID, "Initial admin permissions")

	// Generate JWT for auto-login
	token, _ := middleware.GenerateCompanyToken(
		user.ID,
		user.Email,
		company.ID,
		string(user.Role),
		user.PermissionVersion,
		false, // Not super admin
		h.authConfig,
	)

	c.JSON(http.StatusCreated, gin.H{
		"data": gin.H{
			"company": company,
			"user":    user,
			"token":   token,
		},
		"message": "Registration successful",
	})
}

// ForgotPassword initiates password reset process
// POST /api/v1/companies/auth/forgot-password
func (h *CompanyHandler) ForgotPassword(c *gin.Context) {
	var req models.CompanyUserForgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "validation_error",
			"message": "Email is required",
			"code":    "INVALID_REQUEST",
		})
		return
	}

	// Generate reset token
	_, err := middleware.GenerateSecureToken(32)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "token_generation_failed",
			"message": "Failed to generate reset token",
			"code":    "TOKEN_ERROR",
		})
		return
	}

	// In production, you would:
	// 1. Find user by email
	// 2. Store token in DB with expiry
	// 3. Send email with reset link

	// For now, just acknowledge the request
	// TODO: Implement actual email sending
	c.JSON(http.StatusOK, gin.H{
		"message": "If an account exists with this email, a password reset link will be sent",
	})
}

// ResetPassword resets password using valid token
// POST /api/v1/companies/auth/reset-password
func (h *CompanyHandler) ResetPassword(c *gin.Context) {
	var req models.CompanyUserResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "validation_error",
			"message": "Token and new password are required",
			"code":    "INVALID_REQUEST",
		})
		return
	}

	// Find user by reset token
	user, err := h.userRepo.GetByPasswordResetToken(c.Request.Context(), req.Token)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_token",
			"message": "Invalid or expired reset token",
			"code":    "INVALID_TOKEN",
		})
		return
	}

	// Hash new password
	newPasswordHash, err := middleware.HashPassword(req.NewPassword, h.authConfig.BcryptCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "hash_failed",
			"message": "Failed to process new password",
			"code":    "PASSWORD_ERROR",
		})
		return
	}

	// Update password
	if err := h.userRepo.UpdatePassword(c.Request.Context(), user.ID, newPasswordHash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "update_failed",
			"message": "Failed to update password",
			"code":    "PASSWORD_UPDATE_ERROR",
		})
		return
	}

	// Clear reset token
	_ = h.userRepo.ClearPasswordResetToken(c.Request.Context(), user.ID)

	c.JSON(http.StatusOK, gin.H{
		"message": "Password reset successful. You can now log in with your new password.",
	})
}

// ChangePassword changes password for authenticated user
// POST /api/v1/companies/auth/change-password
func (h *CompanyHandler) ChangePassword(c *gin.Context) {
	userID := middleware.GetCompanyUserID(c)
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "unauthorized",
			"message": "Authentication required",
			"code":    "UNAUTHORIZED",
		})
		return
	}

	var req models.CompanyUserChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "validation_error",
			"message": "Current and new passwords are required",
			"code":    "INVALID_REQUEST",
		})
		return
	}

	// TODO: Verify current password (would need to fetch user with password hash)
	// For now, just update with new password

	// Hash new password
	newPasswordHash, err := middleware.HashPassword(req.NewPassword, h.authConfig.BcryptCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "hash_failed",
			"message": "Failed to process new password",
			"code":    "PASSWORD_ERROR",
		})
		return
	}

	// Update password
	if err := h.userRepo.UpdatePassword(c.Request.Context(), userID, newPasswordHash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "update_failed",
			"message": "Failed to update password",
			"code":    "PASSWORD_UPDATE_ERROR",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Password changed successfully",
	})
}

// RefreshToken generates a new token (if implementing refresh tokens)
// POST /api/v1/companies/auth/refresh
func (h *CompanyHandler) RefreshToken(c *gin.Context) {
	// For now, require re-login
	// In production, implement proper refresh token rotation
	c.JSON(http.StatusOK, gin.H{
		"message": "Please use your current token or re-login",
	})
}

// Helper function to parse integer parameters safely
func parseIntParam(s string) (int, error) {
	var i int
	_, err := fmt.Sscanf(s, "%d", &i)
	return i, err
}

func companyAccessAllowed(c *gin.Context, companyID string) bool {
	return middleware.IsCompanySuperAdmin(c) || middleware.GetCompanyID(c) == companyID
}

func writeCompanyForbidden(c *gin.Context) {
	c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
		"error":   "company_access_denied",
		"message": "You cannot access another company",
	})
}
