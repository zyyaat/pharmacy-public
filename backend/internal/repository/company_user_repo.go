// Package repository - Company User Repository
// Phase 2 - Multi-Tenant SaaS Architecture
// This file handles database operations for company users (with custom auth)
package repository

import (
        "context"
        "fmt"
        "time"

        "github.com/jackc/pgx/v5/pgxpool"
        "github.com/pharmacy-os/backend/internal/models"
)

// ============================================
// Company User Repository
// ============================================

// CompanyUserRepository handles database operations for company users
type CompanyUserRepository struct {
        db *pgxpool.Pool
}

// NewCompanyUserRepository creates a new CompanyUserRepository
func NewCompanyUserRepository(db *pgxpool.Pool) *CompanyUserRepository {
        return &CompanyUserRepository{db: db}
}

// Create inserts a new company user with hashed password
func (r *CompanyUserRepository) Create(ctx context.Context, user *models.CompanyUserCreateRequest, companyID string, passwordHash string) (*models.CompanyUser, error) {
        const query = `
                INSERT INTO company_users (
                        company_id, email, password_hash,
                        first_name, last_name, display_name,
                        phone, avatar_url, role,
                        must_change_password
                ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
                )
                RETURNING 
                        id, company_id, email,
                        last_login_at, login_attempts, locked_until,
                        password_changed_at, must_change_password,
                        first_name, last_name, display_name,
                        avatar_url, phone,
                        role, permission_version,
                        is_active, email_verified_at,
                        preferences, created_at, updated_at, deleted_at
        `

        row := r.db.QueryRow(ctx, query,
                companyID,
                user.Email,
                passwordHash,
                user.FirstName,
                user.LastName,
                user.DisplayName,
                user.Phone,
                user.AvatarURL,
                user.Role,
                user.MustChangePassword,
        )

        var u models.CompanyUser
        err := row.Scan(
                &u.ID, &u.CompanyID, &u.Email,
                &u.LastLoginAt, &u.LoginAttempts, &u.LockedUntil,
                &u.PasswordChangedAt, &u.MustChangePassword,
                &u.FirstName, &u.LastName, &u.DisplayName,
                &u.AvatarURL, &u.Phone,
                &u.Role, &u.PermissionVersion,
                &u.IsActive, &u.EmailVerifiedAt,
                &u.Preferences, &u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to create company user: %w", err)
        }

        return &u, nil
}

// GetByID returns a company user by ID
func (r *CompanyUserRepository) GetByID(ctx context.Context, id string) (*models.CompanyUser, error) {
        const query = `
                SELECT 
                        id, company_id, email,
                        last_login_at, login_attempts, locked_until,
                        password_changed_at, must_change_password,
                        first_name, last_name, display_name,
                        avatar_url, phone,
                        role, permission_version,
                        is_active, email_verified_at,
                        preferences, created_at, updated_at, deleted_at
                FROM company_users
                WHERE id = $1 AND deleted_at IS NULL
        `

        row := r.db.QueryRow(ctx, query, id)

        var u models.CompanyUser
        err := row.Scan(
                &u.ID, &u.CompanyID, &u.Email,
                &u.LastLoginAt, &u.LoginAttempts, &u.LockedUntil,
                &u.PasswordChangedAt, &u.MustChangePassword,
                &u.FirstName, &u.LastName, &u.DisplayName,
                &u.AvatarURL, &u.Phone,
                &u.Role, &u.PermissionVersion,
                &u.IsActive, &u.EmailVerifiedAt,
                &u.Preferences, &u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get company user: %w", err)
        }

        return &u, nil
}

// GetByEmail returns a company user by email and company (for login)
func (r *CompanyUserRepository) GetByEmail(ctx context.Context, email string, companyID string) (*models.CompanyUser, error) {
        const query = `
                SELECT 
                        id, company_id, email,
                        last_login_at, login_attempts, locked_until,
                        password_changed_at, must_change_password,
                        first_name, last_name, display_name,
                        avatar_url, phone,
                        role, permission_version,
                        is_active, email_verified_at,
                        preferences, created_at, updated_at, deleted_at
                FROM company_users
                WHERE email = $1 AND company_id = $2 AND deleted_at IS NULL
                LIMIT 1
        `

        row := r.db.QueryRow(ctx, query, email, companyID)

        var u models.CompanyUser
        err := row.Scan(
                &u.ID, &u.CompanyID, &u.Email,
                &u.LastLoginAt, &u.LoginAttempts, &u.LockedUntil,
                &u.PasswordChangedAt, &u.MustChangePassword,
                &u.FirstName, &u.LastName, &u.DisplayName,
                &u.AvatarURL, &u.Phone,
                &u.Role, &u.PermissionVersion,
                &u.IsActive, &u.EmailVerifiedAt,
                &u.Preferences, &u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get company user by email: %w", err)
        }

        return &u, nil
}

// GetWithPasswordHash returns user with password hash (for authentication only!)
func (r *CompanyUserRepository) GetWithPasswordHash(ctx context.Context, email string, companyID string) (*models.CompanyUser, string, error) {
        const query = `
                SELECT 
                        id, company_id, email, password_hash,
                        last_login_at, login_attempts, locked_until,
                        password_changed_at, must_change_password,
                        first_name, last_name, display_name,
                        avatar_url, phone,
                        role, permission_version,
                        is_active, email_verified_at,
                        preferences, created_at, updated_at, deleted_at
                FROM company_users
                WHERE email = $1 AND company_id = $2 AND deleted_at IS NULL
                LIMIT 1
        `

        row := r.db.QueryRow(ctx, query, email, companyID)

        var u models.CompanyUser
        var passwordHash string
        err := row.Scan(
                &u.ID, &u.CompanyID, &u.Email, &passwordHash,
                &u.LastLoginAt, &u.LoginAttempts, &u.LockedUntil,
                &u.PasswordChangedAt, &u.MustChangePassword,
                &u.FirstName, &u.LastName, &u.DisplayName,
                &u.AvatarURL, &u.Phone,
                &u.Role, &u.PermissionVersion,
                &u.IsActive, &u.EmailVerifiedAt,
                &u.Preferences, &u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
        )

        if err != nil {
                return nil, "", fmt.Errorf("failed to get company user with password: %w", err)
        }

        return &u, passwordHash, nil
}

// Update updates an existing company user
func (r *CompanyUserRepository) Update(ctx context.Context, id string, update *models.CompanyUserUpdateRequest) (*models.CompanyUser, error) {
        const query = `
                UPDATE company_users SET
                        first_name = COALESCE($2, first_name),
                        last_name = COALESCE($3, last_name),
                        display_name = COALESCE($4, display_name),
                        phone = COALESCE($5, phone),
                        avatar_url = COALESCE($6, avatar_url),
                        role = COALESCE($7, role),
                        is_active = COALESCE($8, is_active),
                        updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
                RETURNING 
                        id, company_id, email,
                        last_login_at, login_attempts, locked_until,
                        password_changed_at, must_change_password,
                        first_name, last_name, display_name,
                        avatar_url, phone,
                        role, permission_version,
                        is_active, email_verified_at,
                        preferences, created_at, updated_at, deleted_at
        `

        row := r.db.QueryRow(ctx, query, id,
                update.FirstName, update.LastName, update.DisplayName,
                update.Phone, update.AvatarURL,
                update.Role, update.IsActive,
        )

        var u models.CompanyUser
        err := row.Scan(
                &u.ID, &u.CompanyID, &u.Email,
                &u.LastLoginAt, &u.LoginAttempts, &u.LockedUntil,
                &u.PasswordChangedAt, &u.MustChangePassword,
                &u.FirstName, &u.LastName, &u.DisplayName,
                &u.AvatarURL, &u.Phone,
                &u.Role, &u.PermissionVersion,
                &u.IsActive, &u.EmailVerifiedAt,
                &u.Preferences, &u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to update company user: %w", err)
        }

        return &u, nil
}

// List returns paginated list of company users for a specific company
func (r *CompanyUserRepository) List(ctx context.Context, companyID string, page, pageSize int, role *string, isActive *bool) ([]models.CompanyUser, int64, error) {
        offset := (page - 1) * pageSize
        
        whereClause := "WHERE company_id = $1 AND deleted_at IS NULL"
        args := []interface{}{companyID}
        argNum := 1
        
        if role != nil {
                argNum++
                whereClause += fmt.Sprintf(" AND role = $%d", argNum)
                args = append(args, *role)
        }
        
        if isActive != nil {
                argNum++
                whereClause += fmt.Sprintf(" AND is_active = $%d", argNum)
                args = append(args, *isActive)
        }
        
        // Count query
        countQuery := fmt.Sprintf("SELECT COUNT(*) FROM company_users %s", whereClause)
        var total int64
        err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to count company users: %w", err)
        }
        
        // Data query
        argNum++
        args = append(args, pageSize)
        argNum++
        args = append(args, offset)
        
        dataQuery := fmt.Sprintf(`
                SELECT 
                        id, company_id, email,
                        last_login_at, login_attempts, locked_until,
                        password_changed_at, must_change_password,
                        first_name, last_name, display_name,
                        avatar_url, phone,
                        role, permission_version,
                        is_active, email_verified_at,
                        preferences, created_at, updated_at, deleted_at
                FROM company_users
                %s
                ORDER BY created_at DESC
                LIMIT $%d OFFSET $%d
        `, whereClause, argNum-1, argNum)
        
        rows, err := r.db.Query(ctx, dataQuery, args...)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to query company users: %w", err)
        }
        defer rows.Close()
        
        var users []models.CompanyUser
        for rows.Next() {
                var u models.CompanyUser
                err := rows.Scan(
                        &u.ID, &u.CompanyID, &u.Email,
                        &u.LastLoginAt, &u.LoginAttempts, &u.LockedUntil,
                        &u.PasswordChangedAt, &u.MustChangePassword,
                        &u.FirstName, &u.LastName, &u.DisplayName,
                        &u.AvatarURL, &u.Phone,
                        &u.Role, &u.PermissionVersion,
                        &u.IsActive, &u.EmailVerifiedAt,
                        &u.Preferences, &u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
                )
                if err != nil {
                        return nil, 0, fmt.Errorf("failed to scan company user: %w", err)
                }
                users = append(users, u)
        }
        
        if err := rows.Err(); err != nil {
                return nil, 0, fmt.Errorf("error iterating company users: %w", err)
        }
        
        return users, total, nil
}

// UpdateLoginInfo updates login-related fields after successful authentication
func (r *CompanyUserRepository) UpdateLoginInfo(ctx context.Context, id string) error {
        const query = `
                UPDATE company_users SET
                        last_login_at = NOW(),
                        login_attempts = 0,
                        locked_until = NULL,
                        updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `
        
        _, err := r.db.Exec(ctx, query, id)
        if err != nil {
                return fmt.Errorf("failed to update login info: %w", err)
        }
        
        return nil
}

// IncrementLoginAttempts increments failed login attempts
func (r *CompanyUserRepository) IncrementLoginAttempts(ctx context.Context, id string, maxAttempts int, lockoutDuration time.Duration) (bool, error) {
        const query = `
                UPDATE company_users SET
                        login_attempts = login_attempts + 1,
                        locked_until = CASE 
                                WHEN login_attempts + 1 >= $2 THEN NOW() + $3 
                                ELSE locked_until 
                        END,
                        updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
                RETURNING login_attempts, locked_until
        `
        
        row := r.db.QueryRow(ctx, query, id, maxAttempts, lockoutDuration)
        
        var attempts int
        var lockedUntil *time.Time
        err := row.Scan(&attempts, &lockedUntil)
        if err != nil {
                return false, fmt.Errorf("failed to increment login attempts: %w", err)
        }
        
        // Check if account is now locked
        isLocked := attempts >= maxAttempts
        if lockedUntil != nil && time.Now().Before(*lockedUntil) {
                isLocked = true
        }
        
        return isLocked, nil
}

// UpdatePassword changes user's password
func (r *CompanyUserRepository) UpdatePassword(ctx context.Context, id string, newPasswordHash string) error {
        const query = `
                UPDATE company_users SET
                        password_hash = $2,
                        password_changed_at = NOW(),
                        must_change_password = false,
                        updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `
        
        _, err := r.db.Exec(ctx, query, id, newPasswordHash)
        if err != nil {
                return fmt.Errorf("failed to update password: %w", err)
        }
        
        return nil
}

// SetPasswordResetToken sets password reset token and expiry
func (r *CompanyUserRepository) SetPasswordResetToken(ctx context.Context, id string, token string, expiresAt time.Time) error {
        const query = `
                UPDATE company_users SET
                        password_reset_token = $2,
                        password_reset_expires_at = $3,
                        updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `
        
        _, err := r.db.Exec(ctx, query, id, token, expiresAt)
        if err != nil {
                return fmt.Errorf("failed to set password reset token: %w", err)
        }
        
        return nil
}

// GetByPasswordResetToken finds user by reset token
func (r *CompanyUserRepository) GetByPasswordResetToken(ctx context.Context, token string) (*models.CompanyUser, error) {
        const query = `
                SELECT 
                        id, company_id, email,
                        last_login_at, login_attempts, locked_until,
                        password_changed_at, must_change_password,
                        first_name, last_name, display_name,
                        avatar_url, phone,
                        role, permission_version,
                        is_active, email_verified_at,
                        preferences, created_at, updated_at, deleted_at
                FROM company_users
                WHERE password_reset_token = $1 
                  AND password_reset_expires_at > NOW()
                  AND deleted_at IS NULL
                LIMIT 1
        `

        row := r.db.QueryRow(ctx, query, token)

        var u models.CompanyUser
        err := row.Scan(
                &u.ID, &u.CompanyID, &u.Email,
                &u.LastLoginAt, &u.LoginAttempts, &u.LockedUntil,
                &u.PasswordChangedAt, &u.MustChangePassword,
                &u.FirstName, &u.LastName, &u.DisplayName,
                &u.AvatarURL, &u.Phone,
                &u.Role, &u.PermissionVersion,
                &u.IsActive, &u.EmailVerifiedAt,
                &u.Preferences, &u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get user by reset token: %w", err)
        }

        return &u, nil
}

// ClearPasswordResetToken clears the password reset token after successful reset
func (r *CompanyUserRepository) ClearPasswordResetToken(ctx context.Context, id string) error {
        const query = `
                UPDATE company_users SET
                        password_reset_token = NULL,
                        password_reset_expires_at = NULL,
                        updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `
        
        _, err := r.db.Exec(ctx, query, id)
        if err != nil {
                return fmt.Errorf("failed to clear password reset token: %w", err)
        }
        
        return nil
}

// SoftDelete soft deletes a company user
func (r *CompanyUserRepository) SoftDelete(ctx context.Context, id string) error {
        const query = `
                UPDATE company_users 
                SET deleted_at = NOW(), updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `
        
        result, err := r.db.Exec(ctx, query, id)
        if err != nil {
                return fmt.Errorf("failed to soft delete company user: %w", err)
        }
        
        if result.RowsAffected() == 0 {
                return fmt.Errorf("company user not found or already deleted")
        }
        
        return nil
}

// IncrementPermissionVersion increments permission version (for cache invalidation)
func (r *CompanyUserRepository) IncrementPermissionVersion(ctx context.Context, id string) error {
        const query = `
                UPDATE company_users 
                SET permission_version = permission_version + 1,
                    updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `
        
        _, err := r.db.Exec(ctx, query, id)
        if err != nil {
                return fmt.Errorf("failed to increment permission version: %w", err)
        }
        
        return nil
}

// CheckEmailExists checks if email exists in company (for uniqueness validation)
func (r *CompanyUserRepository) CheckEmailExists(ctx context.Context, email string, companyID string, excludeID string) (bool, error) {
        const query = `
                SELECT EXISTS (
                        SELECT 1 FROM company_users 
                        WHERE email = $1 AND company_id = $2 AND deleted_at IS NULL AND id != $3
                )
        `
        
        var exists bool
        err := r.db.QueryRow(ctx, query, email, companyID, excludeID).Scan(&exists)
        if err != nil {
                return false, fmt.Errorf("failed to check email existence: %w", err)
        }
        
        return exists, nil
}

// GetUserWithPermissions returns user with their permissions populated
func (r *CompanyUserRepository) GetUserWithPermissions(ctx context.Context, id string) (*models.CompanyUser, error) {
        // Get basic user info
        user, err := r.GetByID(ctx, id)
        if err != nil {
                return nil, err
        }
        
        // Get permissions
        const permQuery = `
                SELECT p.key 
                FROM company_user_permissions cup
                JOIN permissions p ON cup.permission_id = p.id
                WHERE cup.company_user_id = $1 AND cup.is_active = true
                ORDER BY p.module, p.key
        `
        
        rows, err := r.db.Query(ctx, permQuery, id)
        if err != nil {
                return nil, fmt.Errorf("failed to get user permissions: %w", err)
        }
        defer rows.Close()
        
        var permissions []string
        for rows.Next() {
                var key string
                if err := rows.Scan(&key); err != nil {
                        return nil, fmt.Errorf("failed to scan permission: %w", err)
                }
                permissions = append(permissions, key)
        }
        
        user.PermissionKeys = permissions
        user.TotalPermissions = len(permissions)
        
        return user, nil
}
