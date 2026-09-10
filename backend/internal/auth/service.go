// Package auth implements application-owned authentication.
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

const (
	CompanyUserPrincipal = "company_user"
	EmployeePrincipal    = "employee"
	VerifyEmailPurpose   = "verify_email"
	ResetPasswordPurpose = "reset_password"
)

const verificationResendCooldown = 60 * time.Second

type AuthRealm string

const (
	PlatformRealm AuthRealm = "platform"
	PharmacyRealm AuthRealm = "pharmacy"
)

var (
	ErrInvalidCredentials = errors.New("invalid email or password")
	ErrAccountLocked      = errors.New("account temporarily locked")
	ErrLoginRateLimited   = errors.New("login temporarily rate limited")
	ErrAccountInactive    = errors.New("account inactive")
	ErrEmailNotVerified   = errors.New("email not verified")
	ErrInvalidToken       = errors.New("invalid or expired token")
	ErrAmbiguousAccount   = errors.New("more than one account matched")
)

// Config controls session lifetime and cookie behavior.
type Config struct {
	AccessTTL     time.Duration
	RefreshTTL    time.Duration
	CookieSecure  bool
	CookieDomain  string
	BrevoAPIKey   string
	MailFromEmail string
	MailFromName  string
	PublicAppURL  string
}

// Principal is the common identity shape used by both account types.
type Principal struct {
	ID                string
	Type              string
	Email             string
	FirstName         string
	LastName          string
	DisplayName       string
	Role              string
	CompanyID         string
	PharmacyID        string
	BranchID          string
	PermissionVersion int
	Locale            string
	PasswordHash      string
	IsActive          bool
	EmailVerified     bool
	LoginAttempts     int
	LockedUntil       *time.Time
}

type SessionTokens struct {
	AccessToken      string
	RefreshToken     string
	AccessExpiresAt  time.Time
	RefreshExpiresAt time.Time
}

type RequestMeta struct {
	IPAddress string
	UserAgent string
}

type Service struct {
	db                  *pgxpool.Pool
	cfg                 Config
	loginThrottleMu     sync.Mutex
	superAdminThrottles map[string]superAdminThrottle
}

func NewService(db *pgxpool.Pool, cfg Config) *Service {
	if cfg.AccessTTL <= 0 {
		cfg.AccessTTL = 15 * time.Minute
	}
	if cfg.RefreshTTL <= 0 {
		cfg.RefreshTTL = 30 * 24 * time.Hour
	}
	return &Service{
		db:                  db,
		cfg:                 cfg,
		superAdminThrottles: make(map[string]superAdminThrottle),
	}
}

func (s *Service) Config() Config {
	return s.cfg
}

func principalAllowedInRealm(principal *Principal, realm AuthRealm) bool {
	if principal == nil || !principal.IsActive {
		return false
	}
	switch realm {
	case PlatformRealm:
		return principal.Type == CompanyUserPrincipal && principal.Role == "super_admin"
	case PharmacyRealm:
		if principal.PharmacyID == "" || principal.Role == "super_admin" {
			return false
		}
		if principal.Type == EmployeePrincipal {
			return true
		}
		return principal.Type == CompanyUserPrincipal &&
			(principal.Role == "company_admin" ||
				principal.Role == "company_manager")
	default:
		return false
	}
}

func (s *Service) FindPrincipal(ctx context.Context, email, principalType, tenantID string) (*Principal, error) {
	email = normalizeEmail(email)
	switch principalType {
	case CompanyUserPrincipal:
		return s.findCompanyUser(ctx, email, tenantID)
	case EmployeePrincipal:
		return s.findEmployee(ctx, email, tenantID)
	case "":
		company, companyErr := s.findCompanyUser(ctx, email, tenantID)
		employee, employeeErr := s.findEmployee(ctx, email, tenantID)
		if companyErr == nil && employeeErr == nil {
			return nil, ErrAmbiguousAccount
		}
		if companyErr == nil {
			return company, nil
		}
		if employeeErr == nil {
			return employee, nil
		}
		return nil, pgx.ErrNoRows
	default:
		return nil, fmt.Errorf("unsupported account type")
	}
}

func (s *Service) Authenticate(ctx context.Context, accessToken string, realm AuthRealm) (*Principal, error) {
	hash := tokenHash(accessToken)
	var principalType, principalID string
	err := s.db.QueryRow(ctx, `
		SELECT principal_type, principal_id::text
		FROM auth_sessions
		WHERE access_token_hash = $1
	  AND auth_realm = $2
		  AND revoked_at IS NULL
		  AND access_expires_at > NOW()
		  AND refresh_expires_at > NOW()
	`, hash, string(realm)).Scan(&principalType, &principalID)
	if err != nil {
		return nil, ErrInvalidToken
	}
	_, _ = s.db.Exec(ctx, `UPDATE auth_sessions SET last_used_at = NOW() WHERE access_token_hash = $1`, hash)
	principal, err := s.findPrincipalByID(ctx, principalType, principalID)
	if err != nil || !principalAllowedInRealm(principal, realm) {
		return nil, ErrInvalidToken
	}
	return principal, nil
}

func (s *Service) Login(ctx context.Context, email, password, principalType, tenantID string, realm AuthRealm, meta RequestMeta) (*Principal, *SessionTokens, error) {
	principal, err := s.FindPrincipal(ctx, email, principalType, tenantID)
	if err != nil {
		// Run the same expensive password operation for unknown accounts.
		_ = bcrypt.CompareHashAndPassword([]byte(dummyPasswordHash), []byte(password))
		return nil, nil, ErrInvalidCredentials
	}
	if !principalAllowedInRealm(principal, realm) {
		_ = bcrypt.CompareHashAndPassword([]byte(dummyPasswordHash), []byte(password))
		return nil, nil, ErrInvalidCredentials
	}

	if principal.Role != "super_admin" && principal.LockedUntil != nil && time.Now().Before(*principal.LockedUntil) {
		return nil, nil, ErrAccountLocked
	}
	superAdminRateLimited := principal.Role == "super_admin" &&
		s.superAdminLoginRateLimited(principal.Email, meta.IPAddress)
	if !principal.IsActive {
		return nil, nil, ErrAccountInactive
	}
	if principal.PasswordHash == "" || bcrypt.CompareHashAndPassword([]byte(principal.PasswordHash), []byte(password)) != nil {
		if principal.Role == "super_admin" {
			if superAdminRateLimited || s.recordSuperAdminFailure(principal.Email, meta.IPAddress) {
				return nil, nil, ErrLoginRateLimited
			}
			return nil, nil, ErrInvalidCredentials
		}
		if locked, updateErr := s.recordFailedLogin(ctx, principal); updateErr == nil && locked {
			return nil, nil, ErrAccountLocked
		}
		return nil, nil, ErrInvalidCredentials
	}
	if !principal.EmailVerified {
		return nil, nil, ErrEmailNotVerified
	}

	if err := s.recordSuccessfulLogin(ctx, principal); err != nil {
		return nil, nil, fmt.Errorf("update login state: %w", err)
	}
	if principal.Role == "super_admin" {
		s.clearSuperAdminFailures(principal.Email, meta.IPAddress)
	}
	tokens, err := s.createSession(ctx, principal, realm, meta)
	if err != nil {
		return nil, nil, err
	}
	return principal, tokens, nil
}

func (s *Service) Refresh(ctx context.Context, refreshToken string, realm AuthRealm, meta RequestMeta) (*Principal, *SessionTokens, error) {
	hash := tokenHash(refreshToken)
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback(ctx)

	var sessionID, familyID, principalType, principalID string
	err = tx.QueryRow(ctx, `
		SELECT id::text, family_id::text, principal_type, principal_id::text
		FROM auth_sessions
		WHERE refresh_token_hash = $1
	  AND auth_realm = $2
		  AND revoked_at IS NULL
		  AND refresh_expires_at > NOW()
		FOR UPDATE
	`, hash, string(realm)).Scan(&sessionID, &familyID, &principalType, &principalID)
	if err != nil {
		return nil, nil, ErrInvalidToken
	}

	principal, err := s.findPrincipalByID(ctx, principalType, principalID)
	if err != nil || !principal.IsActive || !principalAllowedInRealm(principal, realm) {
		return nil, nil, ErrInvalidToken
	}

	access, err := randomToken(32)
	if err != nil {
		return nil, nil, err
	}
	refresh, err := randomToken(48)
	if err != nil {
		return nil, nil, err
	}
	now := time.Now().UTC()
	tokens := &SessionTokens{
		AccessToken:      access,
		RefreshToken:     refresh,
		AccessExpiresAt:  now.Add(s.cfg.AccessTTL),
		RefreshExpiresAt: now.Add(s.cfg.RefreshTTL),
	}

	var replacementID string
	err = tx.QueryRow(ctx, `
		INSERT INTO auth_sessions (
	family_id, auth_realm, principal_type, principal_id, access_token_hash,
			refresh_token_hash, access_expires_at, refresh_expires_at,
			user_agent, ip_address
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NULLIF($10, '')::inet)
	RETURNING id::text
	`, familyID, string(realm), principalType, principalID, tokenHash(access), tokenHash(refresh),
		tokens.AccessExpiresAt, tokens.RefreshExpiresAt, meta.UserAgent, meta.IPAddress).Scan(&replacementID)
	if err != nil {
		return nil, nil, fmt.Errorf("create rotated session: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE auth_sessions
		SET revoked_at = NOW(), replaced_by_session_id = $2
		WHERE id = $1
	`, sessionID, replacementID); err != nil {
		return nil, nil, fmt.Errorf("revoke rotated session: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, nil, err
	}
	return principal, tokens, nil
}

func (s *Service) RevokeTokens(ctx context.Context, accessToken, refreshToken string) error {
	_, err := s.db.Exec(ctx, `
		UPDATE auth_sessions SET revoked_at = NOW()
		WHERE revoked_at IS NULL
		  AND (access_token_hash = $1 OR refresh_token_hash = $2)
	`, tokenHash(accessToken), tokenHash(refreshToken))
	return err
}

func (s *Service) RevokeAll(ctx context.Context, principal *Principal) error {
	_, err := s.db.Exec(ctx, `
		UPDATE auth_sessions SET revoked_at = NOW()
		WHERE principal_type = $1 AND principal_id = $2 AND revoked_at IS NULL
	`, principal.Type, principal.ID)
	return err
}

func (s *Service) RevokeAllInRealm(ctx context.Context, principal *Principal, realm AuthRealm) error {
	_, err := s.db.Exec(ctx, `
	UPDATE auth_sessions SET revoked_at = NOW()
	WHERE principal_type = $1 AND principal_id = $2
	  AND auth_realm = $3 AND revoked_at IS NULL
	`, principal.Type, principal.ID, string(realm))
	return err
}

func (s *Service) ChangePassword(ctx context.Context, principal *Principal, currentPassword, newPassword string) error {
	if principal.PasswordHash == "" || bcrypt.CompareHashAndPassword([]byte(principal.PasswordHash), []byte(currentPassword)) != nil {
		return ErrInvalidCredentials
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	if err := s.updatePassword(ctx, principal, string(hash)); err != nil {
		return err
	}
	return s.RevokeAll(ctx, principal)
}

func (s *Service) CreateEmailToken(ctx context.Context, principal *Principal, purpose string) (string, error) {
	raw, err := randomToken(32)
	if purpose == VerifyEmailPurpose {
		raw, err = randomVerificationCode()
	}
	if err != nil {
		return "", err
	}
	_, err = s.db.Exec(ctx, `
		UPDATE auth_email_tokens SET used_at = NOW()
		WHERE principal_type = $1 AND principal_id = $2 AND purpose = $3 AND used_at IS NULL
	`, principal.Type, principal.ID, purpose)
	if err != nil {
		return "", err
	}
	_, err = s.db.Exec(ctx, `
		INSERT INTO auth_email_tokens (principal_type, principal_id, purpose, token_hash, expires_at)
		VALUES ($1, $2, $3, $4, NOW() + $5::interval)
	`, principal.Type, principal.ID, purpose, tokenHash(raw), tokenLifetime(purpose))
	if err != nil {
		return "", err
	}
	return raw, nil
}

func (s *Service) CreateEmailTokenIfDue(ctx context.Context, principal *Principal, purpose string) (string, bool, error) {
	var recentlyIssued bool
	err := s.db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM auth_email_tokens
			WHERE principal_type = $1
			  AND principal_id = $2
			  AND purpose = $3
			  AND used_at IS NULL
			  AND expires_at > NOW()
			  AND created_at > NOW() - ($4::bigint * INTERVAL '1 second')
		)
	`, principal.Type, principal.ID, purpose, int64(verificationResendCooldown/time.Second)).Scan(&recentlyIssued)
	if err != nil {
		return "", false, err
	}
	if recentlyIssued {
		return "", false, nil
	}
	code, err := s.CreateEmailToken(ctx, principal, purpose)
	if err != nil {
		return "", false, err
	}
	return code, true, nil
}

func (s *Service) InvalidateEmailToken(ctx context.Context, principal *Principal, purpose string) error {
	_, err := s.db.Exec(ctx, `
		UPDATE auth_email_tokens
		SET used_at = NOW()
		WHERE principal_type = $1
		  AND principal_id = $2
		  AND purpose = $3
		  AND used_at IS NULL
	`, principal.Type, principal.ID, purpose)
	return err
}

func (s *Service) ConsumeEmailToken(ctx context.Context, raw, purpose string) (*Principal, error) {
	var id, principalType, principalID string
	err := s.db.QueryRow(ctx, `
		UPDATE auth_email_tokens
		SET used_at = NOW()
		WHERE token_hash = $1 AND purpose = $2 AND used_at IS NULL AND expires_at > NOW()
		RETURNING id::text, principal_type, principal_id::text
	`, tokenHash(raw), purpose).Scan(&id, &principalType, &principalID)
	if err != nil {
		return nil, ErrInvalidToken
	}
	return s.findPrincipalByID(ctx, principalType, principalID)
}

func (s *Service) ConsumeEmailVerificationCode(ctx context.Context, email, code string) (*Principal, error) {
	var id, principalType, principalID string
	err := s.db.QueryRow(ctx, `
UPDATE auth_email_tokens t
SET used_at = NOW()
WHERE t.token_hash = $1
  AND t.purpose = $2
  AND t.used_at IS NULL
  AND t.expires_at > NOW()
  AND (
    (t.principal_type = 'company_user' AND EXISTS (
      SELECT 1 FROM company_users cu
      WHERE cu.id = t.principal_id
        AND LOWER(cu.email) = LOWER($3)
        AND cu.deleted_at IS NULL
    ))
    OR
    (t.principal_type = 'employee' AND EXISTS (
      SELECT 1 FROM employees e
      WHERE e.id = t.principal_id
        AND LOWER(e.email) = LOWER($3)
    ))
  )
RETURNING t.id::text, t.principal_type, t.principal_id::text
`, tokenHash(code), VerifyEmailPurpose, normalizeEmail(email)).Scan(&id, &principalType, &principalID)
	if err != nil {
		return nil, ErrInvalidToken
	}
	return s.findPrincipalByID(ctx, principalType, principalID)
}

func (s *Service) MarkEmailVerified(ctx context.Context, principal *Principal) error {
	query := `UPDATE company_users SET email_verified_at = NOW(), email_verification_token = NULL WHERE id = $1`
	if principal.Type == EmployeePrincipal {
		query = `UPDATE employees SET email_verified_at = NOW() WHERE id = $1`
	}
	_, err := s.db.Exec(ctx, query, principal.ID)
	return err
}

func (s *Service) UpdatePasswordFromReset(ctx context.Context, principal *Principal, newPassword string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	if err := s.updatePassword(ctx, principal, string(hash)); err != nil {
		return err
	}
	return s.RevokeAll(ctx, principal)
}

// SetLocale stores the UI language preference for the authenticated
// principal. The allowlist is validated by the handler and by CHECK
// constraints, so an unknown value never reaches the database.
func (s *Service) SetLocale(ctx context.Context, principal *Principal, locale string) error {
	query := `UPDATE company_users SET locale = $2 WHERE id = $1 AND deleted_at IS NULL`
	if principal.Type == EmployeePrincipal {
		query = `UPDATE employees SET locale = $2 WHERE id = $1`
	}
	_, err := s.db.Exec(ctx, query, principal.ID, locale)
	return err
}

func (s *Service) RegisterCompany(ctx context.Context, companyName, companyEmail, firstName, lastName, email, password string) (*Principal, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var trialDays int
	if err := tx.QueryRow(ctx, `
		SELECT COALESCE((setting_value->>'default_trial_days')::int, 30)
		FROM platform_settings
		WHERE setting_key = 'trial'
	`).Scan(&trialDays); err != nil {
		return nil, fmt.Errorf("load default trial duration: %w", err)
	}
	if trialDays < 1 {
		trialDays = 30
	}

	var companyID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO companies (name, email, status, plan, trial_ends_at)
		VALUES ($1, $2, 'trial', 'free', NOW() + ($3 * INTERVAL '1 day'))
		RETURNING id::text
	`, strings.TrimSpace(companyName), normalizeEmail(companyEmail), trialDays).Scan(&companyID); err != nil {
		return nil, fmt.Errorf("create company: %w", err)
	}

	var accountID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO accounts (
			company_id, company_name, contact_email, status,
			subscription_plan, default_currency, timezone, locale, trial_ends_at
		) VALUES ($1, $2, $3, 'trial', 'free', 'EGP', 'Africa/Cairo', 'ar-EG',
		          NOW() + ($4 * INTERVAL '1 day'))
		RETURNING id::text
	`, companyID, strings.TrimSpace(companyName), normalizeEmail(companyEmail), trialDays).Scan(&accountID); err != nil {
		return nil, fmt.Errorf("create account: %w", err)
	}

	var pharmacyID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO pharmacies (
			account_id, name, email, country, is_main_branch, currency
		) VALUES ($1, $2, $3, 'EG', true, 'EGP')
		RETURNING id::text
	`, accountID, strings.TrimSpace(companyName), normalizeEmail(companyEmail)).Scan(&pharmacyID); err != nil {
		return nil, fmt.Errorf("create pharmacy: %w", err)
	}

	var branchID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO branches (pharmacy_id, name, code, country)
		VALUES ($1, 'الفرع الرئيسي', 'MAIN', 'EG')
		RETURNING id::text
	`, pharmacyID).Scan(&branchID); err != nil {
		return nil, fmt.Errorf("create main branch: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE pharmacies SET default_branch_id = $2 WHERE id = $1
	`, pharmacyID, branchID); err != nil {
		return nil, fmt.Errorf("set default branch: %w", err)
	}

	var userID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO company_users (
			company_id, email, password_hash, first_name, last_name, role
		) VALUES ($1, $2, $3, $4, $5, 'company_admin')
		RETURNING id::text
	`, companyID, normalizeEmail(email), string(hash), strings.TrimSpace(firstName), strings.TrimSpace(lastName)).Scan(&userID); err != nil {
		return nil, fmt.Errorf("create company owner: %w", err)
	}

	// The central registration flow must provision the same minimum company
	// permissions as the legacy registration handler. Do this before commit so
	// a newly verified owner can immediately use the authenticated API.
	if _, err := tx.Exec(ctx, `
		INSERT INTO company_user_permissions (company_user_id, permission_id, granted_by, notes)
		SELECT $1, p.id, $1, 'Initial company owner permissions'
		FROM permissions p
		WHERE p.key = ANY($2::text[])
		ON CONFLICT (company_user_id, permission_id)
		WHERE revoked_at IS NULL
		DO UPDATE SET revoked_at = NULL, revocation_reason = NULL
	`, userID, []string{
		"companies.view", "companies.update",
		"company_users.view", "company_users.create", "company_users.update",
		"accounts.view", "accounts.create", "accounts.update",
	}); err != nil {
		return nil, fmt.Errorf("grant initial company permissions: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return s.findPrincipalByID(ctx, CompanyUserPrincipal, userID)
}

func (s *Service) findCompanyUser(ctx context.Context, email, companyID string) (*Principal, error) {
	var p Principal
	err := s.db.QueryRow(ctx, `
		SELECT cu.id::text, cu.email, cu.first_name, cu.last_name, COALESCE(cu.display_name, ''),
		       cu.role::text, cu.company_id::text, COALESCE(p.id::text, ''),
		       COALESCE(b.id::text, ''), COALESCE(cu.password_hash, ''),
		       cu.is_active, cu.email_verified_at IS NOT NULL, cu.login_attempts, cu.locked_until,
		       cu.permission_version, COALESCE(cu.locale, 'ar')
		FROM company_users cu
		LEFT JOIN accounts a ON a.company_id = cu.company_id AND a.deleted_at IS NULL
		LEFT JOIN pharmacies p ON p.account_id = a.id AND p.is_active = true AND p.is_main_branch = true
		LEFT JOIN branches b ON b.id = p.default_branch_id AND b.is_active = true
		WHERE LOWER(cu.email) = LOWER($1)
		  AND ($2 = '' OR cu.company_id::text = $2)
		  AND cu.deleted_at IS NULL
		ORDER BY cu.created_at
		LIMIT 1
	`, email, companyID).Scan(
		&p.ID, &p.Email, &p.FirstName, &p.LastName, &p.DisplayName, &p.Role,
		&p.CompanyID, &p.PharmacyID, &p.BranchID, &p.PasswordHash, &p.IsActive, &p.EmailVerified,
		&p.LoginAttempts, &p.LockedUntil, &p.PermissionVersion, &p.Locale,
	)
	if err != nil {
		return nil, err
	}
	p.Type = CompanyUserPrincipal
	return &p, nil
}

func (s *Service) findEmployee(ctx context.Context, email, pharmacyID string) (*Principal, error) {
	var p Principal
	err := s.db.QueryRow(ctx, `
		SELECT id::text, email, first_name, last_name, COALESCE(display_name, ''),
		       role::text, pharmacy_id::text, COALESCE(branch_id::text, ''),
		       COALESCE(password_hash, ''), is_active,
		       email_verified_at IS NOT NULL, login_attempts, locked_until,
		       permission_version, COALESCE(locale, 'ar')
		FROM employees
		WHERE LOWER(email) = LOWER($1)
		  AND ($2 = '' OR pharmacy_id::text = $2)
		ORDER BY created_at
		LIMIT 1
	`, email, pharmacyID).Scan(
		&p.ID, &p.Email, &p.FirstName, &p.LastName, &p.DisplayName, &p.Role,
		&p.PharmacyID, &p.BranchID, &p.PasswordHash, &p.IsActive,
		&p.EmailVerified, &p.LoginAttempts, &p.LockedUntil, &p.PermissionVersion, &p.Locale,
	)
	if err != nil {
		return nil, err
	}
	p.Type = EmployeePrincipal
	return &p, nil
}

func (s *Service) findPrincipalByID(ctx context.Context, principalType, id string) (*Principal, error) {
	if principalType == CompanyUserPrincipal {
		var p Principal
		err := s.db.QueryRow(ctx, `
			SELECT cu.id::text, cu.email, cu.first_name, cu.last_name, COALESCE(cu.display_name, ''),
			       cu.role::text, cu.company_id::text, COALESCE(p.id::text, ''),
			       COALESCE(b.id::text, ''), COALESCE(cu.password_hash, ''),
			       cu.is_active, cu.email_verified_at IS NOT NULL, cu.login_attempts, cu.locked_until,
			       cu.permission_version, COALESCE(cu.locale, 'ar')
			FROM company_users cu
			LEFT JOIN accounts a ON a.company_id = cu.company_id AND a.deleted_at IS NULL
			LEFT JOIN pharmacies p ON p.account_id = a.id AND p.is_active = true AND p.is_main_branch = true
			LEFT JOIN branches b ON b.id = p.default_branch_id AND b.is_active = true
			WHERE cu.id = $1 AND cu.deleted_at IS NULL
		`, id).Scan(&p.ID, &p.Email, &p.FirstName, &p.LastName, &p.DisplayName, &p.Role,
			&p.CompanyID, &p.PharmacyID, &p.BranchID, &p.PasswordHash, &p.IsActive, &p.EmailVerified, &p.LoginAttempts,
			&p.LockedUntil, &p.PermissionVersion, &p.Locale)
		if err != nil {
			return nil, err
		}
		p.Type = CompanyUserPrincipal
		return &p, nil
	}
	var p Principal
	err := s.db.QueryRow(ctx, `
		SELECT id::text, email, first_name, last_name, COALESCE(display_name, ''),
		       role::text, pharmacy_id::text, COALESCE(branch_id::text, ''),
		       COALESCE(password_hash, ''), is_active,
		       email_verified_at IS NOT NULL, login_attempts, locked_until,
		       permission_version, COALESCE(locale, 'ar')
		FROM employees WHERE id = $1
	`, id).Scan(&p.ID, &p.Email, &p.FirstName, &p.LastName, &p.DisplayName, &p.Role,
		&p.PharmacyID, &p.BranchID, &p.PasswordHash, &p.IsActive, &p.EmailVerified,
		&p.LoginAttempts, &p.LockedUntil, &p.PermissionVersion, &p.Locale)
	if err != nil {
		return nil, err
	}
	p.Type = EmployeePrincipal
	return &p, nil
}

func (s *Service) createSession(ctx context.Context, principal *Principal, realm AuthRealm, meta RequestMeta) (*SessionTokens, error) {
	access, err := randomToken(32)
	if err != nil {
		return nil, err
	}
	refresh, err := randomToken(48)
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC()
	tokens := &SessionTokens{
		AccessToken:      access,
		RefreshToken:     refresh,
		AccessExpiresAt:  now.Add(s.cfg.AccessTTL),
		RefreshExpiresAt: now.Add(s.cfg.RefreshTTL),
	}
	_, err = s.db.Exec(ctx, `
		INSERT INTO auth_sessions (
	auth_realm, principal_type, principal_id, access_token_hash, refresh_token_hash,
			access_expires_at, refresh_expires_at, user_agent, ip_address
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULLIF($9, '')::inet)
	`, string(realm), principal.Type, principal.ID, tokenHash(access), tokenHash(refresh),
		tokens.AccessExpiresAt, tokens.RefreshExpiresAt, meta.UserAgent, meta.IPAddress)
	if err != nil {
		return nil, fmt.Errorf("create session: %w", err)
	}
	return tokens, nil
}

// CreateSession creates a browser session for a newly registered principal.
// Registration uses this instead of requiring the user to enter credentials a
// second time after the account has been created.
func (s *Service) CreateSession(ctx context.Context, principal *Principal, realm AuthRealm, meta RequestMeta) (*SessionTokens, error) {
	return s.createSession(ctx, principal, realm, meta)
}

func (s *Service) recordFailedLogin(ctx context.Context, principal *Principal) (bool, error) {
	lockedUntil := time.Now().UTC().Add(15 * time.Minute)
	var attempts int
	var err error
	if principal.Type == CompanyUserPrincipal {
		err = s.db.QueryRow(ctx, `
			UPDATE company_users
			SET login_attempts = login_attempts + 1,
			    locked_until = CASE WHEN login_attempts + 1 >= 5 THEN $2 ELSE locked_until END
			WHERE id = $1
			RETURNING login_attempts
		`, principal.ID, lockedUntil).Scan(&attempts)
	} else {
		err = s.db.QueryRow(ctx, `
			UPDATE employees
			SET login_attempts = login_attempts + 1,
			    locked_until = CASE WHEN login_attempts + 1 >= 5 THEN $2 ELSE locked_until END
			WHERE id = $1
			RETURNING login_attempts
		`, principal.ID, lockedUntil).Scan(&attempts)
	}
	return attempts >= 5, err
}

func (s *Service) recordSuccessfulLogin(ctx context.Context, principal *Principal) error {
	query := `UPDATE company_users SET login_attempts = 0, locked_until = NULL, last_login_at = NOW() WHERE id = $1`
	if principal.Type == EmployeePrincipal {
		query = `UPDATE employees SET login_attempts = 0, locked_until = NULL, last_login_at = NOW() WHERE id = $1`
	}
	_, err := s.db.Exec(ctx, query, principal.ID)
	return err
}

type superAdminThrottle struct {
	failures     int
	blockedUntil time.Time
	lastFailure  time.Time
}

const (
	superAdminFailureWindow = 15 * time.Minute
	superAdminFailureLimit  = 5
)

func (s *Service) superAdminThrottleKey(email, ipAddress string) string {
	return normalizeEmail(email) + "|" + strings.TrimSpace(ipAddress)
}

func (s *Service) recordSuperAdminFailure(email, ipAddress string) bool {
	now := time.Now()
	key := s.superAdminThrottleKey(email, ipAddress)

	s.loginThrottleMu.Lock()
	defer s.loginThrottleMu.Unlock()

	entry := s.superAdminThrottles[key]
	if !entry.lastFailure.IsZero() && now.Sub(entry.lastFailure) >= superAdminFailureWindow {
		entry = superAdminThrottle{}
	}
	entry.failures++
	entry.lastFailure = now
	if entry.failures >= superAdminFailureLimit {
		entry.blockedUntil = now.Add(superAdminFailureWindow)
	}
	s.superAdminThrottles[key] = entry
	return !entry.blockedUntil.IsZero() && now.Before(entry.blockedUntil)
}

func (s *Service) superAdminLoginRateLimited(email, ipAddress string) bool {
	now := time.Now()
	key := s.superAdminThrottleKey(email, ipAddress)

	s.loginThrottleMu.Lock()
	defer s.loginThrottleMu.Unlock()

	entry, ok := s.superAdminThrottles[key]
	if !ok {
		return false
	}
	if !entry.blockedUntil.IsZero() && now.Before(entry.blockedUntil) {
		return true
	}
	if !entry.lastFailure.IsZero() && now.Sub(entry.lastFailure) >= superAdminFailureWindow {
		delete(s.superAdminThrottles, key)
	}
	return false
}

func (s *Service) clearSuperAdminFailures(email, ipAddress string) {
	s.loginThrottleMu.Lock()
	defer s.loginThrottleMu.Unlock()
	delete(s.superAdminThrottles, s.superAdminThrottleKey(email, ipAddress))
}

func (s *Service) updatePassword(ctx context.Context, principal *Principal, hash string) error {
	query := `UPDATE company_users SET password_hash = $2, password_changed_at = NOW() WHERE id = $1`
	if principal.Type == EmployeePrincipal {
		query = `UPDATE employees SET password_hash = $2, password_changed_at = NOW() WHERE id = $1`
	}
	_, err := s.db.Exec(ctx, query, principal.ID, hash)
	return err
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func tokenLifetime(purpose string) string {
	if purpose == VerifyEmailPurpose {
		return "24 hours"
	}
	return "1 hour"
}

func randomToken(size int) (string, error) {
	bytes := make([]byte, size)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func randomVerificationCode() (string, error) {
	value, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", value.Int64()+100000), nil
}

func tokenHash(value string) []byte {
	hash := sha256.Sum256([]byte(value))
	return hash[:]
}

const dummyPasswordHash = "$2a$12$C6UzMDM.H6dfI/f/IKcEe.Vh6YyKjF7Wk5lD6t0x8eF7Q9W6j7vQ2"
