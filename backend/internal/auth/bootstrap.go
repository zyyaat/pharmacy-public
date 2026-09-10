package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
)

const superAdminBootstrapKey = "super_admin"

// BootstrapSuperAdmin creates the single platform administrator on a new
// production database. The database migration provides the singleton table
// and unique role constraint; this method owns the first data record.
func (s *Service) BootstrapSuperAdmin(
	ctx context.Context,
	email string,
	password string,
	firstName string,
	lastName string,
	companyName string,
) error {
	email = normalizeEmail(email)
	firstName = strings.TrimSpace(firstName)
	lastName = strings.TrimSpace(lastName)
	companyName = strings.TrimSpace(companyName)
	if email == "" {
		return errors.New("bootstrap super admin configuration is incomplete")
	}

	tx, err := s.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin super admin bootstrap: %w", err)
	}
	defer tx.Rollback(ctx)

	// Prevent two autoscale instances from bootstrapping simultaneously.
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext('pharmacy_os_bootstrap_super_admin'))`); err != nil {
		return fmt.Errorf("lock super admin bootstrap: %w", err)
	}

	var statePrincipalID, stateEmail string
	stateErr := tx.QueryRow(ctx, `
		SELECT principal_id::text, email
		FROM platform_bootstrap_state
		WHERE bootstrap_key = $1
		FOR UPDATE
	`, superAdminBootstrapKey).Scan(&statePrincipalID, &stateEmail)
	if stateErr == nil {
		var role, existingEmail string
		var active bool
		if err := tx.QueryRow(ctx, `
			SELECT role::text, email, is_active
			FROM company_users
			WHERE id = $1 AND deleted_at IS NULL
		`, statePrincipalID).Scan(&role, &existingEmail, &active); err != nil {
			return fmt.Errorf("validate bootstrapped super admin: %w", err)
		}
		if role != "super_admin" || !active || normalizeEmail(existingEmail) != email || normalizeEmail(stateEmail) != email {
			return fmt.Errorf("super admin bootstrap state does not match BOOTSTRAP_SUPER_ADMIN_EMAIL")
		}
		return nil
	}
	if !errors.Is(stateErr, pgx.ErrNoRows) {
		return fmt.Errorf("read super admin bootstrap state: %w", stateErr)
	}

	// Existing databases may contain the account created by the earlier
	// bootstrap implementation. Adopt it only when it matches the configured
	// identity; never silently choose a different administrator.
	var existingID, existingEmail string
	var superAdmins int
	if err := tx.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM company_users
		WHERE role = 'super_admin'
	`).Scan(&superAdmins); err != nil {
		return fmt.Errorf("count existing super admins: %w", err)
	}
	if superAdmins > 1 {
		return fmt.Errorf("found %d super admins; manual cleanup is required before bootstrap", superAdmins)
	}
	if superAdmins == 1 {
		var deleted bool
		if err := tx.QueryRow(ctx, `
			SELECT id::text, email, deleted_at IS NOT NULL
			FROM company_users
			WHERE role = 'super_admin'
			LIMIT 1
		`).Scan(&existingID, &existingEmail, &deleted); err != nil {
			return fmt.Errorf("read existing super admin: %w", err)
		}
		if deleted {
			return errors.New("the existing super admin is deleted; manual recovery is required")
		}
		if normalizeEmail(existingEmail) != email {
			return fmt.Errorf("an active super admin already exists with a different email")
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO platform_bootstrap_state (bootstrap_key, principal_id, email)
			VALUES ($1, $2, $3)
		`, superAdminBootstrapKey, existingID, email); err != nil {
			return fmt.Errorf("adopt existing super admin bootstrap state: %w", err)
		}
		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("commit existing super admin bootstrap state: %w", err)
		}
		return nil
	}

	if password == "" || firstName == "" || lastName == "" || companyName == "" {
		return errors.New("bootstrap super admin password and profile configuration are required for a new database")
	}

	var emailExists bool
	if err := tx.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM company_users
			WHERE LOWER(email) = $1 AND deleted_at IS NULL
		)
	`, email).Scan(&emailExists); err != nil {
		return fmt.Errorf("check bootstrap email: %w", err)
	}
	if emailExists {
		return fmt.Errorf("bootstrap email already belongs to a non-super-admin account")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash bootstrap password: %w", err)
	}

	var companyID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO companies (name, email, status, plan)
		VALUES ($1, $2, 'active', 'enterprise')
		RETURNING id::text
	`, companyName, email).Scan(&companyID); err != nil {
		return fmt.Errorf("create bootstrap company: %w", err)
	}

	var accountID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO accounts (
			company_id, company_name, contact_email, status,
			subscription_plan, default_currency, timezone, locale
		) VALUES ($1, $2, $3, 'active', 'enterprise', 'EGP', 'Africa/Cairo', 'ar-EG')
		RETURNING id::text
	`, companyID, companyName, email).Scan(&accountID); err != nil {
		return fmt.Errorf("create bootstrap account: %w", err)
	}

	var pharmacyID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO pharmacies (
			account_id, name, email, country, is_main_branch, currency
		) VALUES ($1, $2, $3, 'EG', true, 'EGP')
		RETURNING id::text
	`, accountID, companyName, email).Scan(&pharmacyID); err != nil {
		return fmt.Errorf("create bootstrap pharmacy: %w", err)
	}

	var branchID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO branches (pharmacy_id, name, code, country, email)
		VALUES ($1, 'الفرع الرئيسي', 'MAIN', 'EG', $2)
		RETURNING id::text
	`, pharmacyID, email).Scan(&branchID); err != nil {
		return fmt.Errorf("create bootstrap branch: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE pharmacies SET default_branch_id = $2 WHERE id = $1
	`, pharmacyID, branchID); err != nil {
		return fmt.Errorf("set bootstrap default branch: %w", err)
	}

	var userID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO company_users (
			company_id, email, password_hash, first_name, last_name,
			role, email_verified_at
		) VALUES ($1, $2, $3, $4, $5, 'super_admin', NOW())
		RETURNING id::text
	`, companyID, email, string(hash), firstName, lastName).Scan(&userID); err != nil {
		return fmt.Errorf("create bootstrap super admin: %w", err)
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO company_user_permissions (company_user_id, permission_id, granted_by, notes)
		SELECT $1, p.id, $1, 'Initial platform administrator permissions'
		FROM permissions p
		ON CONFLICT (company_user_id, permission_id)
		WHERE revoked_at IS NULL
		DO UPDATE SET revoked_at = NULL, revocation_reason = NULL
	`, userID); err != nil {
		return fmt.Errorf("grant bootstrap permissions: %w", err)
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO platform_bootstrap_state (bootstrap_key, principal_id, email)
		VALUES ($1, $2, $3)
	`, superAdminBootstrapKey, userID, email); err != nil {
		return fmt.Errorf("record super admin bootstrap state: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit super admin bootstrap: %w", err)
	}
	return nil
}
