// Package models - Holding Company / SaaS Platform Models
// Phase 2 - Multi-Tenant Architecture
// These models represent the company layer that sits above pharmacy accounts
package models

import (
	"time"
)

// ============================================
// Company Status & Plan Constants
// ============================================

type CompanyStatus string

const (
	CompanyStatusActive    CompanyStatus = "active"
	CompanyStatusSuspended CompanyStatus = "suspended"
	CompanyStatusTrial     CompanyStatus = "trial"
	CompanyStatusCancelled CompanyStatus = "cancelled"
)

type CompanyPlan string

const (
	CompanyPlanFree        CompanyPlan = "free"
	CompanyPlanStarter     CompanyPlan = "starter"
	CompanyPlanProfessional CompanyPlan = "professional"
	CompanyPlanEnterprise  CompanyPlan = "enterprise"
	CompanyPlanCustom      CompanyPlan = "custom"
)

type CompanyUserRole string

const (
	CompanyRoleSuperAdmin   CompanyUserRole = "super_admin"
	CompanyRoleAdmin        CompanyUserRole = "company_admin"
	CompanyRoleManager      CompanyUserRole = "company_manager"
	CompanyRoleViewer       CompanyUserRole = "company_viewer"
)

// ============================================
// Company Model (Holding Company / SaaS Customer)
// ============================================

// Company represents a holding company (SaaS customer) that can own multiple pharmacy accounts
type Company struct {
	ID                              string                 `json:"id"`
	Name                            string                 `json:"name"`
	NameAr                          *string                `json:"name_ar,omitempty"`
	LegalName                       *string                `json:"legal_name,omitempty"`
	RegistrationNumber              *string                `json:"registration_number,omitempty"`
	Email                           string                 `json:"email"`
	Phone                           *string                `json:"phone,omitempty"`
	Website                         *string                `json:"website,omitempty"`
	AddressLine1                    *string                `json:"address_line1,omitempty"`
	AddressLine2                    *string                `json:"address_line2,omitempty"`
	City                            *string                `json:"city,omitempty"`
	StateProvince                   *string                `json:"state_province,omitempty"`
	PostalCode                      *string                `json:"postal_code,omitempty"`
	Country                         string                 `json:"country"`
	Status                          CompanyStatus          `json:"status"`
	Plan                            CompanyPlan            `json:"plan"`
	TrialEndsAt                     *time.Time             `json:"trial_ends_at,omitempty"`
	SubscriptionCurrentPeriodStart  *time.Time             `json:"subscription_current_period_start,omitempty"`
	SubscriptionCurrentPeriodEnd    *time.Time             `json:"subscription_current_period_end,omitempty"`
	MaxAccounts                     int                    `json:"max_accounts"`
	MaxUsersPerAccount              int                    `json:"max_users_per_account"`
	DefaultCurrency                  string                 `json:"default_currency"`
	Timezone                        string                 `json:"timezone"`
	Locale                          string                 `json:"locale"`
	Settings                        map[string]interface{} `json:"settings,omitempty"`
	LogoURL                         *string                `json:"logo_url,omitempty"`
	PrimaryColor                    *string                `json:"primary_color,omitempty"`
	SecondaryColor                  *string                `json:"secondary_color,omitempty"`
	CreatedAt                       time.Time              `json:"created_at"`
	UpdatedAt                       time.Time              `json:"updated_at"`
	DeletedAt                       *time.Time             `json:"deleted_at,omitempty"`
	IsActive                        bool                   `json:"is_active"`

	// Computed fields (not in DB)
	TotalAccounts *int `json:"total_accounts,omitempty"`
	ActiveAccounts *int `json:"active_accounts,omitempty"`
	TotalUsers    *int `json:"total_users,omitempty"`
}

// CompanyCreateRequest represents the request to create a new company
type CompanyCreateRequest struct {
	Name               string                 `json:"name" validate:"required,min=2,max=255"`
	NameAr             *string                `json:"name_ar,omitempty" validate:"max=255"`
	LegalName          *string                `json:"legal_name,omitempty" validate:"max=255"`
	RegistrationNumber *string                `json:"registration_number,omitempty" validate:"max=100"`
	Email              string                 `json:"email" validate:"required,email"`
	Phone              *string                `json:"phone,omitempty" validate:"max=50"`
	Website            *string                `json:"website,omitempty" validate:"max=255,url"`
	AddressLine1       *string                `json:"address_line1,omitempty" validate:"max=255"`
	AddressLine2       *string                `json:"address_line2,omitempty" validate:"max=255"`
	City               *string                `json:"city,omitempty" validate:"max=100"`
	StateProvince      *string                `json:"state_province,omitempty" validate:"max=100"`
	PostalCode         *string                `json:"postal_code,omitempty" validate:"max=20"`
	Country            string                 `json:"country" validate:"max=100"`
	Plan               CompanyPlan            `json:"plan" validate:"required,oneof=free starter professional enterprise custom"`
	DefaultCurrency    string                 `json:"default_currency" validate:"max=10"`
	Timezone           string                 `json:"timezone" validate:"max=100"`
	Locale             string                 `json:"locale" validate:"max=10"`
	Settings           map[string]interface{} `json:"settings,omitempty"`
	MaxAccounts        *int                   `json:"max_accounts" validate:"min=1,max=1000"`
	MaxUsersPerAccount *int                   `json:"max_users_per_account" validate:"min=1,max=1000"`
}

// CompanyUpdateRequest represents the request to update a company
type CompanyUpdateRequest struct {
	Name               *string                `json:"name,omitempty" validate:"omitempty,min=2,max=255"`
	NameAr             *string                `json:"name_ar,omitempty" validate:"omitempty,max=255"`
	LegalName          *string                `json:"legal_name,omitempty" validate:"omitempty,max=255"`
	RegistrationNumber *string                `json:"registration_number,omitempty" validate:"omitempty,max=100"`
	Phone              *string                `json:"phone,omitempty" validate:"omitempty,max=50"`
	Website            *string                `json:"website,omitempty" validate:"omitempty,max=255,url"`
	AddressLine1       *string                `json:"address_line1,omitempty" validate:"omitempty,max=255"`
	AddressLine2       *string                `json:"address_line2,omitempty" validate:"omitempty,max=255"`
	City               *string                `json:"city,omitempty" validate:"omitempty,max=100"`
	StateProvince      *string                `json:"state_province,omitempty" validate:"omitempty,max=100"`
	PostalCode         *string                `json:"postal_code,omitempty" validate:"omitempty,max=20"`
	Country            *string                `json:"country,omitempty" validate:"omitempty,max=100"`
	DefaultCurrency    *string                `json:"default_currency,omitempty" validate:"omitempty,max=10"`
	Timezone           *string                `json:"timezone,omitempty" validate:"omitempty,max=100"`
	Locale             *string                `json:"locale,omitempty" validate:"omitempty,max=10"`
	Settings           map[string]interface{} `json:"settings,omitempty"`
	LogoURL            *string                `json:"logo_url,omitempty" validate:"omitempty,url"`
	PrimaryColor      *string                `json:"primary_color,omitempty" validate:"omitempty,len=7"`
	SecondaryColor    *string                `json:"secondary_color,omitempty" validate:"omitempty,len=7"`
	MaxAccounts       *int                   `json:"max_accounts,omitempty" validate:"omitempty,min=1,max=1000"`
	MaxUsersPerAccount *int                  `json:"max_users_per_account,omitempty" validate:"omitempty,min=1,max=1000"`
}

// CompanyListResponse represents paginated company list response
type CompanyListResponse struct {
	Companies []Company `json:"companies"`
	Total     int64     `json:"total"`
	Page      int       `json:"page"`
	PageSize  int       `json:"page_size"`
}

// ============================================
// Company User Model (Company-level Users with Custom Auth)
// ============================================

// CompanyUser represents a user who manages a holding company (NOT a pharmacy employee)
type CompanyUser struct {
	ID                   string          `json:"id"`
	CompanyID            string          `json:"company_id"`
	Email                string          `json:"email"` // No password_hash in JSON!
	LastLoginAt          *time.Time      `json:"last_login_at,omitempty"`
	LoginAttempts        int             `json:"login_attempts"`
	LockedUntil          *time.Time      `json:"locked_until,omitempty"`
	PasswordChangedAt    time.Time       `json:"password_changed_at"`
	MustChangePassword   bool            `json:"must_change_password"`
	FirstName            string          `json:"first_name"`
	LastName             string          `json:"last_name"`
	DisplayName          *string         `json:"display_name,omitempty"`
	AvatarURL            *string         `json:"avatar_url,omitempty"`
	Phone                *string         `json:"phone,omitempty"`
	Role                 CompanyUserRole `json:"role"`
	PermissionVersion    int             `json:"permission_version"`
	IsActive             bool            `json:"is_active"`
	EmailVerifiedAt      *time.Time      `json:"email_verified_at,omitempty"`
	Preferences          map[string]interface{} `json:"preferences,omitempty"`
	CreatedAt            time.Time       `json:"created_at"`
	UpdatedAt            time.Time       `json:"updated_at"`
	DeletedAt            *time.Time      `json:"deleted_at,omitempty"`

	// Computed fields
	PermissionKeys []string `json:"permission_keys,omitempty"`
	TotalPermissions int    `json:"total_permissions,omitempty"`
}

// CompanyUserCreateRequest represents the request to create a new company user
type CompanyUserCreateRequest struct {
	Email           string          `json:"email" validate:"required,email"`
	Password        string          `json:"password" validate:"required,min=8,max=128"`
	FirstName       string          `json:"first_name" validate:"required,min=1,max=100"`
	LastName        string          `json:"last_name" validate:"required,min=1,max=100"`
	DisplayName     *string         `json:"display_name,omitempty" validate:"omitempty,max=200"`
	Phone           *string         `json:"phone,omitempty" validate:"omitempty,max=50"`
	AvatarURL       *string         `json:"avatar_url,omitempty" validate:"omitempty,url"`
	Role            CompanyUserRole `json:"role" validate:"required,oneof=super_admin company_admin company_manager company_viewer"`
	MustChangePassword bool         `json:"must_change_password"`
}

// CompanyUserUpdateRequest represents the request to update a company user
type CompanyUserUpdateRequest struct {
	FirstName  *string         `json:"first_name,omitempty" validate:"omitempty,min=1,max=100"`
	LastName   *string         `json:"last_name,omitempty" validate:"omitempty,min=1,max=100"`
	DisplayName *string        `json:"display_name,omitempty" validate:"omitempty,max=200"`
	Phone      *string         `json:"phone,omitempty" validate:"omitempty,max=50"`
	AvatarURL  *string         `json:"avatar_url,omitempty" validate:"omitempty,url"`
	Role       *CompanyUserRole `json:"role,omitempty" validate:"omitempty,oneof=super_admin company_admin company_manager company_viewer"`
	IsActive   *bool           `json:"is_active,omitempty"`
}

// CompanyUserLoginRequest represents login request for company user
type CompanyUserLoginRequest struct {
	Email    string `json:"email" validate:"required,email"`
	Password string `json:"password" validate:"required"`
}

// CompanyUserLoginResponse represents successful login response
type CompanyUserLoginResponse struct {
	User        CompanyUser `json:"user"`
	AccessToken string      `json:"access_token"`
	TokenType   string      `json:"token_type"`
	ExpiresIn   int64       `json:"expires_in"` // seconds
	Company     Company     `json:"company"`
}

// CompanyUserChangePasswordRequest represents password change request
type CompanyUserChangePasswordRequest struct {
	CurrentPassword string `json:"current_password" validate:"required"`
	NewPassword     string `json:"new_password" validate:"required,min=8,max=128"`
}

// CompanyUserForgotPasswordRequest represents forgot password request
type CompanyUserForgotPasswordRequest struct {
	Email string `json:"email" validate:"required,email"`
}

// CompanyUserResetPasswordRequest represents password reset request
type CompanyUserResetPasswordRequest struct {
	Token       string `json:"token" validate:"required"`
	NewPassword string `json:"new_password" validate:"required,min=8,max=128"`
}

// ============================================
// Company User Permission Model
// ============================================

// CompanyUserPermission represents a permission granted to a company user
type CompanyUserPermission struct {
	ID              string     `json:"id"`
	CompanyUserID   string     `json:"company_user_id"`
	PermissionID    int        `json:"permission_id"`
	PermissionKey   string     `json:"permission_key"` // From join
	PermissionName  string     `json:"permission_name"` // From join
	GrantedBy       string     `json:"granted_by"`
	GrantedByName   string     `json:"granted_by_name"` // From join
	GrantedAt       time.Time  `json:"granted_at"`
	RevokedBy       *string    `json:"revoked_by,omitempty"`
	RevokedAt       *time.Time `json:"revoked_at,omitempty"`
	RevocationReason *string   `json:"revocation_reason,omitempty"`
	IsActive        bool       `json:"is_active"`
	Notes           *string    `json:"notes,omitempty"`
}

// GrantPermissionRequest represents request to grant a permission
type GrantPermissionRequest struct {
	PermissionKey string `json:"permission_key" validate:"required"`
	Notes         string `json:"notes,omitempty"`
}

// RevokePermissionRequest represents request to revoke a permission
type RevokePermissionRequest struct {
	PermissionKey string `json:"permission_key" validate:"required"`
	Reason        string `json:"reason,omitempty"`
}

// BatchGrantPermissionsRequest represents batch permission grant
type BatchGrantPermissionsRequest struct {
	PermissionKeys []string `json:"permission_keys" validate:"required,min=1,max=50"`
	Notes          string   `json:"notes,omitempty"`
}

// ============================================
// JWT Claims for Company Users
// ============================================

// CompanyJWTClaims represents JWT claims for company user authentication
type CompanyJWTClaims struct {
	UserID           string          `json:"user_id"`
	Email            string          `json:"email"`
	CompanyID        string          `json:"company_id"`
	Role             CompanyUserRole `json:"role"`
	PermissionVersion int            `json:"permission_version"`
	IsSuperAdmin     bool            `json:"is_super_admin"`
	CustomClaims     `json:"-"`
}

// CustomClaims embeds standard claims
type CustomClaims struct {
	// Will be embedded from jwt.RegisteredClaims
}

// ============================================
// Account Update: Add CompanyID
// ============================================

// Note: Account model already exists in models.go
// We just need to ensure it has CompanyID field
// This is handled by adding the field if not present

// AccountWithCompany extends Account with company info
type AccountWithCompany struct {
	Account
	CompanyName string `json:"company_name"`
	CompanyID   string `json:"company_id"`
}
