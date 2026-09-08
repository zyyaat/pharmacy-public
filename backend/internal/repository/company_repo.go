// Package repository - Holding Company / SaaS Platform Repositories
// Phase 2 - Multi-Tenant Architecture
// This file handles database operations for companies (holding companies/SaaS customers)
package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/pharmacy-os/backend/internal/models"
)

// ============================================
// Company Repository
// ============================================

// CompanyRepository handles database operations for holding companies
type CompanyRepository struct {
	db *pgxpool.Pool
}

// NewCompanyRepository creates a new CompanyRepository
func NewCompanyRepository(db *pgxpool.Pool) *CompanyRepository {
	return &CompanyRepository{db: db}
}

// Create inserts a new company and returns the created company with ID
func (r *CompanyRepository) Create(ctx context.Context, company *models.CompanyCreateRequest) (*models.Company, error) {
	const query = `
		INSERT INTO companies (
			name, name_ar, legal_name, registration_number,
			email, phone, website,
			address_line1, address_line2, city, state_province, postal_code, country,
			plan, default_currency, timezone, locale,
			max_accounts, max_users_per_account, settings
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
			$14, $15, $16, $17, $18, $19, $20
		)
		RETURNING 
			id, name, name_ar, legal_name, registration_number,
			email, phone, website,
			address_line1, address_line2, city, state_province, postal_code, country,
			status, plan, trial_ends_at,
			subscription_current_period_start, subscription_current_period_end,
			max_accounts, max_users_per_account,
			default_currency, timezone, locale, settings,
			logo_url, primary_color, secondary_color,
			created_at, updated_at, deleted_at, is_active
	`

	row := r.db.QueryRow(ctx, query,
		company.Name,
		company.NameAr,
		company.LegalName,
		company.RegistrationNumber,
		company.Email,
		company.Phone,
		company.Website,
		company.AddressLine1,
		company.AddressLine2,
		company.City,
		company.StateProvince,
		company.PostalCode,
		company.Country,
		company.Plan,
		company.DefaultCurrency,
		company.Timezone,
		company.Locale,
		company.MaxAccounts,
		company.MaxUsersPerAccount,
		company.Settings,
	)

	var c models.Company
	err := row.Scan(
		&c.ID, &c.Name, &c.NameAr, &c.LegalName, &c.RegistrationNumber,
		&c.Email, &c.Phone, &c.Website,
		&c.AddressLine1, &c.AddressLine2, &c.City, &c.StateProvince, &c.PostalCode, &c.Country,
		&c.Status, &c.Plan, &c.TrialEndsAt,
		&c.SubscriptionCurrentPeriodStart, &c.SubscriptionCurrentPeriodEnd,
		&c.MaxAccounts, &c.MaxUsersPerAccount,
		&c.DefaultCurrency, &c.Timezone, &c.Locale, &c.Settings,
		&c.LogoURL, &c.PrimaryColor, &c.SecondaryColor,
		&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt, &c.IsActive,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to create company: %w", err)
	}

	return &c, nil
}

// GetByID returns a company by ID
func (r *CompanyRepository) GetByID(ctx context.Context, id string) (*models.Company, error) {
	const query = `
		SELECT 
			id, name, name_ar, legal_name, registration_number,
			email, phone, website,
			address_line1, address_line2, city, state_province, postal_code, country,
			status, plan, trial_ends_at,
			subscription_current_period_start, subscription_current_period_end,
			max_accounts, max_users_per_account,
			default_currency, timezone, locale, settings,
			logo_url, primary_color, secondary_color,
			created_at, updated_at, deleted_at, is_active
		FROM companies
		WHERE id = $1 AND deleted_at IS NULL
	`

	row := r.db.QueryRow(ctx, query, id)

	var c models.Company
	err := row.Scan(
		&c.ID, &c.Name, &c.NameAr, &c.LegalName, &c.RegistrationNumber,
		&c.Email, &c.Phone, &c.Website,
		&c.AddressLine1, &c.AddressLine2, &c.City, &c.StateProvince, &c.PostalCode, &c.Country,
		&c.Status, &c.Plan, &c.TrialEndsAt,
		&c.SubscriptionCurrentPeriodStart, &c.SubscriptionCurrentPeriodEnd,
		&c.MaxAccounts, &c.MaxUsersPerAccount,
		&c.DefaultCurrency, &c.Timezone, &c.Locale, &c.Settings,
		&c.LogoURL, &c.PrimaryColor, &c.SecondaryColor,
		&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt, &c.IsActive,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to get company: %w", err)
	}

	return &c, nil
}

// GetByEmail returns a company by email (for login/registration)
func (r *CompanyRepository) GetByEmail(ctx context.Context, email string) (*models.Company, error) {
	const query = `
		SELECT 
			id, name, name_ar, legal_name, registration_number,
			email, phone, website,
			address_line1, address_line2, city, state_province, postal_code, country,
			status, plan, trial_ends_at,
			subscription_current_period_start, subscription_current_period_end,
			max_accounts, max_users_per_account,
			default_currency, timezone, locale, settings,
			logo_url, primary_color, secondary_color,
			created_at, updated_at, deleted_at, is_active
		FROM companies
		WHERE email = $1 AND deleted_at IS NULL
		LIMIT 1
	`

	row := r.db.QueryRow(ctx, query, email)

	var c models.Company
	err := row.Scan(
		&c.ID, &c.Name, &c.NameAr, &c.LegalName, &c.RegistrationNumber,
		&c.Email, &c.Phone, &c.Website,
		&c.AddressLine1, &c.AddressLine2, &c.City, &c.StateProvince, &c.PostalCode, &c.Country,
		&c.Status, &c.Plan, &c.TrialEndsAt,
		&c.SubscriptionCurrentPeriodStart, &c.SubscriptionCurrentPeriodEnd,
		&c.MaxAccounts, &c.MaxUsersPerAccount,
		&c.DefaultCurrency, &c.Timezone, &c.Locale, &c.Settings,
		&c.LogoURL, &c.PrimaryColor, &c.SecondaryColor,
		&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt, &c.IsActive,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to get company by email: %w", err)
	}

	return &c, nil
}

// Update updates an existing company
func (r *CompanyRepository) Update(ctx context.Context, id string, update *models.CompanyUpdateRequest) (*models.Company, error) {
	const query = `
		UPDATE companies SET
			name = COALESCE($2, name),
			name_ar = COALESCE($3, name_ar),
			legal_name = COALESCE($4, legal_name),
			registration_number = COALESCE($5, registration_number),
			phone = COALESCE($6, phone),
			website = COALESCE($7, website),
			address_line1 = COALESCE($8, address_line1),
			address_line2 = COALESCE($9, address_line2),
			city = COALESCE($10, city),
			state_province = COALESCE($11, state_province),
			postal_code = COALESCE($12, postal_code),
			country = COALESCE($13, country),
			default_currency = COALESCE($14, default_currency),
			timezone = COALESCE($15, timezone),
			locale = COALESCE($16, locale),
			settings = COALESCE($17, settings),
			logo_url = COALESCE($18, logo_url),
			primary_color = COALESCE($19, primary_color),
			secondary_color = COALESCE($20, secondary_color),
			max_accounts = COALESCE($21, max_accounts),
			max_users_per_account = COALESCE($22, max_users_per_account),
			updated_at = NOW()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING 
			id, name, name_ar, legal_name, registration_number,
			email, phone, website,
			address_line1, address_line2, city, state_province, postal_code, country,
			status, plan, trial_ends_at,
			subscription_current_period_start, subscription_current_period_end,
			max_accounts, max_users_per_account,
			default_currency, timezone, locale, settings,
			logo_url, primary_color, secondary_color,
			created_at, updated_at, deleted_at, is_active
	`

	row := r.db.QueryRow(ctx, query, id,
		update.Name, update.NameAr, update.LegalName, update.RegistrationNumber,
		update.Phone, update.Website,
		update.AddressLine1, update.AddressLine2,
		update.City, update.StateProvince, update.PostalCode, update.Country,
		update.DefaultCurrency, update.Timezone, update.Locale,
		update.Settings,
		update.LogoURL, update.PrimaryColor, update.SecondaryColor,
		update.MaxAccounts, update.MaxUsersPerAccount,
	)

	var c models.Company
	err := row.Scan(
		&c.ID, &c.Name, &c.NameAr, &c.LegalName, &c.RegistrationNumber,
		&c.Email, &c.Phone, &c.Website,
		&c.AddressLine1, &c.AddressLine2, &c.City, &c.StateProvince, &c.PostalCode, &c.Country,
		&c.Status, &c.Plan, &c.TrialEndsAt,
		&c.SubscriptionCurrentPeriodStart, &c.SubscriptionCurrentPeriodEnd,
		&c.MaxAccounts, &c.MaxUsersPerAccount,
		&c.DefaultCurrency, &c.Timezone, &c.Locale, &c.Settings,
		&c.LogoURL, &c.PrimaryColor, &c.SecondaryColor,
		&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt, &c.IsActive,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to update company: %w", err)
	}

	return &c, nil
}

// List returns paginated list of companies
func (r *CompanyRepository) List(ctx context.Context, page, pageSize int, status *string) ([]models.Company, int64, error) {
	offset := (page - 1) * pageSize
	
	// Build WHERE clause dynamically
	whereClause := "WHERE deleted_at IS NULL"
	args := []interface{}{}
	argNum := 0
	
	if status != nil {
		argNum++
		whereClause += fmt.Sprintf(" AND status = $%d", argNum)
		args = append(args, *status)
	}
	
	// Count query
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM companies %s", whereClause)
	var total int64
	err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to count companies: %w", err)
	}
	
	// Data query
	argNum++
	args = append(args, pageSize)
	argNum++
	args = append(args, offset)
	
	dataQuery := fmt.Sprintf(`
		SELECT 
			id, name, name_ar, legal_name, registration_number,
			email, phone, website,
			address_line1, address_line2, city, state_province, postal_code, country,
			status, plan, trial_ends_at,
			subscription_current_period_start, subscription_current_period_end,
			max_accounts, max_users_per_account,
			default_currency, timezone, locale, settings,
			logo_url, primary_color, secondary_color,
			created_at, updated_at, deleted_at, is_active
		FROM companies
		%s
		ORDER BY created_at DESC
		LIMIT $%d OFFSET $%d
	`, whereClause, argNum-1, argNum)
	
	rows, err := r.db.Query(ctx, dataQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query companies: %w", err)
	}
	defer rows.Close()
	
	var companies []models.Company
	for rows.Next() {
		var c models.Company
		err := rows.Scan(
			&c.ID, &c.Name, &c.NameAr, &c.LegalName, &c.RegistrationNumber,
			&c.Email, &c.Phone, &c.Website,
			&c.AddressLine1, &c.AddressLine2, &c.City, &c.StateProvince, &c.PostalCode, &c.Country,
			&c.Status, &c.Plan, &c.TrialEndsAt,
			&c.SubscriptionCurrentPeriodStart, &c.SubscriptionCurrentPeriodEnd,
			&c.MaxAccounts, &c.MaxUsersPerAccount,
			&c.DefaultCurrency, &c.Timezone, &c.Locale, &c.Settings,
			&c.LogoURL, &c.PrimaryColor, &c.SecondaryColor,
			&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt, &c.IsActive,
		)
		if err != nil {
			return nil, 0, fmt.Errorf("failed to scan company: %w", err)
		}
		companies = append(companies, c)
	}
	
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("error iterating companies: %w", err)
	}
	
	return companies, total, nil
}

// SoftDelete soft deletes a company (sets deleted_at)
func (r *CompanyRepository) SoftDelete(ctx context.Context, id string) error {
	const query = `
		UPDATE companies 
		SET deleted_at = NOW(), updated_at = NOW()
		WHERE id = $1 AND deleted_at IS NULL
	`
	
	result, err := r.db.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to soft delete company: %w", err)
	}
	
	rowsAffected := result.RowsAffected()
	if rowsAffected == 0 {
		return fmt.Errorf("company not found or already deleted")
	}
	
	return nil
}

// UpdateStatus updates company status (active/suspended/cancelled)
func (r *CompanyRepository) UpdateStatus(ctx context.Context, id string, status models.CompanyStatus) error {
	const query = `
		UPDATE companies 
		SET status = $1, updated_at = NOW()
		WHERE id = $2 AND deleted_at IS NULL
	`
	
	result, err := r.db.Exec(ctx, query, status, id)
	if err != nil {
		return fmt.Errorf("failed to update company status: %w", err)
	}
	
	if result.RowsAffected() == 0 {
		return fmt.Errorf("company not found")
	}
	
	return nil
}

// UpdateSubscription updates company subscription info
func (r *CompanyRepository) UpdateSubscription(
	ctx context.Context, 
	id string, 
	plan models.CompanyPlan, 
	periodStart, periodEnd *time.Time,
) error {
	const query = `
		UPDATE companies 
		SET 
			plan = $1,
			subscription_current_period_start = $2,
			subscription_current_period_end = $3,
			updated_at = NOW()
		WHERE id = $4 AND deleted_at IS NULL
	`
	
	_, err := r.db.Exec(ctx, query, plan, periodStart, periodEnd, id)
	if err != nil {
		return fmt.Errorf("failed to update company subscription: %w", err)
	}
	
	return nil
}

// GetSummary returns company summary with account/user counts
func (r *CompanyRepository) GetSummary(ctx context.Context, id string) (*models.Company, error) {
	const query = `
		SELECT 
			c.id, c.name, c.name_ar, c.legal_name, c.registration_number,
			c.email, c.phone, c.website,
			c.address_line1, c.address_line2, c.city, c.state_province, c.postal_code, c.country,
			c.status, c.plan, c.trial_ends_at,
			c.subscription_current_period_start, c.subscription_current_period_end,
			c.max_accounts, c.max_users_per_account,
			c.default_currency, c.timezone, c.locale, c.settings,
			c.logo_url, c.primary_color, c.secondary_color,
			c.created_at, c.updated_at, c.deleted_at, c.is_active,
			COUNT(DISTINCT CASE WHEN a.deleted_at IS NULL THEN a.id END) as total_accounts,
			COUNT(DISTINCT CASE WHEN a.deleted_at IS NULL AND a.status = 'active' THEN a.id END) as active_accounts,
			COUNT(DISTINCT CASE WHEN cu.deleted_at IS NULL AND cu.is_active = true THEN cu.id END) as total_users
		FROM companies c
		LEFT JOIN accounts a ON a.company_id = c.id
		LEFT JOIN company_users cu ON cu.company_id = c.id
		WHERE c.id = $1 AND c.deleted_at IS NULL
		GROUP BY c.id
	`

	row := r.db.QueryRow(ctx, query, id)

	var c models.Company
	var totalAccounts, activeAccounts, totalUsers int
	err := row.Scan(
		&c.ID, &c.Name, &c.NameAr, &c.LegalName, &c.RegistrationNumber,
		&c.Email, &c.Phone, &c.Website,
		&c.AddressLine1, &c.AddressLine2, &c.City, &c.StateProvince, &c.PostalCode, &c.Country,
		&c.Status, &c.Plan, &c.TrialEndsAt,
		&c.SubscriptionCurrentPeriodStart, &c.SubscriptionCurrentPeriodEnd,
		&c.MaxAccounts, &c.MaxUsersPerAccount,
		&c.DefaultCurrency, &c.Timezone, &c.Locale, &c.Settings,
		&c.LogoURL, &c.PrimaryColor, &c.SecondaryColor,
		&c.CreatedAt, &c.UpdatedAt, &c.DeletedAt, &c.IsActive,
		&totalAccounts, &activeAccounts, &totalUsers,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to get company summary: %w", err)
	}

	c.TotalAccounts = &totalAccounts
	c.ActiveAccounts = &activeAccounts
	c.TotalUsers = &totalUsers

	return &c, nil
}

// CheckEmailExists checks if a company email already exists
func (r *CompanyRepository) CheckEmailExists(ctx context.Context, email string, excludeID string) (bool, error) {
	const query = `
		SELECT EXISTS (
			SELECT 1 FROM companies 
			WHERE email = $1 AND deleted_at IS NULL AND id != $2
		)
	`
	
	var exists bool
	err := r.db.QueryRow(ctx, query, email, excludeID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check email existence: %w", err)
	}
	
	return exists, nil
}
