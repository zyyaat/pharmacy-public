// Package repository - Company User Permission Repository
// Phase 2 - Multi-Tenant SaaS Architecture
// This file handles database operations for company user permissions
package repository

import (
        "context"
        "fmt"

        "github.com/jackc/pgx/v5/pgxpool"
        "github.com/pharmacy-os/backend/internal/models"
)

// ============================================
// Company User Permission Repository
// ============================================

// CompanyUserPermissionRepository handles database operations for company user permissions
type CompanyUserPermissionRepository struct {
        db *pgxpool.Pool
}

// NewCompanyUserPermissionRepository creates a new CompanyUserPermissionRepository
func NewCompanyUserPermissionRepository(db *pgxpool.Pool) *CompanyUserPermissionRepository {
        return &CompanyUserPermissionRepository{db: db}
}

// Grant grants a permission to a company user
func (r *CompanyUserPermissionRepository) Grant(
        ctx context.Context,
        companyUserID string,
        permissionKey string,
        grantedBy string,
        notes string,
) (*models.CompanyUserPermission, error) {
        const query = `
                INSERT INTO company_user_permissions (company_user_id, permission_id, granted_by, notes)
                SELECT $1, p.id, $2, $3
                FROM permissions p
                WHERE p.key = $4
                RETURNING 
                        id, company_user_id, permission_id,
                        granted_by, granted_at,
                        revoked_by, revoked_at, revocation_reason,
                        is_active, notes
        `

        row := r.db.QueryRow(ctx, query, companyUserID, grantedBy, notes, permissionKey)

        var perm models.CompanyUserPermission
        var permissionID int
        err := row.Scan(
                &perm.ID, &perm.CompanyUserID, &permissionID,
                &perm.GrantedBy, &perm.GrantedAt,
                &perm.RevokedBy, &perm.RevokedAt, &perm.RevocationReason,
                &perm.IsActive, &perm.Notes,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to grant permission: %w", err)
        }

        perm.PermissionKey = permissionKey

        return &perm, nil
}

// Revoke revokes (soft deletes) a permission from a company user
func (r *CompanyUserPermissionRepository) Revoke(
        ctx context.Context,
        companyUserID string,
        permissionKey string,
        revokedBy string,
        reason string,
) error {
        const query = `
                UPDATE company_user_permissions SET
                        revoked_by = $1,
                        revoked_at = NOW(),
                        revocation_reason = $2,
                        is_active = false
                WHERE company_user_id = $3
                  AND permission_id = (SELECT id FROM permissions WHERE key = $4)
                  AND is_active = true
        `

        result, err := r.db.Exec(ctx, query, revokedBy, reason, companyUserID, permissionKey)
        if err != nil {
                return fmt.Errorf("failed to revoke permission: %w", err)
        }

        if result.RowsAffected() == 0 {
                return fmt.Errorf("active permission not found")
        }

        return nil
}

// Check checks if a user has a specific permission
func (r *CompanyUserPermissionRepository) Check(ctx context.Context, companyUserID string, permissionKey string) (bool, error) {
        const query = `
                SELECT EXISTS (
                        SELECT 1 FROM company_user_permissions cup
                        JOIN permissions p ON cup.permission_id = p.id
                        WHERE cup.company_user_id = $1 
                          AND p.key = $2 
                          AND cup.is_active = true
                )
        `

        var hasPerm bool
        err := r.db.QueryRow(ctx, query, companyUserID, permissionKey).Scan(&hasPerm)
        if err != nil {
                return false, fmt.Errorf("failed to check permission: %w", err)
        }

        return hasPerm, nil
}

// GetUserPermissions returns all active permissions for a user
func (r *CompanyUserPermissionRepository) GetUserPermissions(ctx context.Context, companyUserID string) ([]models.CompanyUserPermission, error) {
        const query = `
                SELECT 
                        cup.id, cup.company_user_id, cup.permission_id,
                        p.key as permission_key, p.name as permission_name,
                        cup.granted_by, gu_granter.first_name || ' ' || gu_granter.last_name as granted_by_name,
                        cup.granted_at,
                        cup.revoked_by, cup.revoked_at, cup.revocation_reason,
                        cup.is_active, cup.notes
                FROM company_user_permissions cup
                JOIN permissions p ON cup.permission_id = p.id
                LEFT JOIN company_users gu_granter ON cup.granted_by = gu_granter.id
                WHERE cup.company_user_id = $1
                ORDER BY p.module, p.key
        `

        rows, err := r.db.Query(ctx, query, companyUserID)
        if err != nil {
                return nil, fmt.Errorf("failed to get user permissions: %w", err)
        }
        defer rows.Close()

        var permissions []models.CompanyUserPermission
        for rows.Next() {
                var perm models.CompanyUserPermission
                var permissionID int
                err := rows.Scan(
                        &perm.ID, &perm.CompanyUserID, &permissionID,
                        &perm.PermissionKey, &perm.PermissionName,
                        &perm.GrantedBy, &perm.GrantedByName,
                        &perm.GrantedAt,
                        &perm.RevokedBy, &perm.RevokedAt, &perm.RevocationReason,
                        &perm.IsActive, &perm.Notes,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan permission: %w", err)
                }
                permissions = append(permissions, perm)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating permissions: %w", err)
        }

        return permissions, nil
}

// GetUserActivePermissionKeys returns just the permission keys (for caching/authorization)
func (r *CompanyUserPermissionRepository) GetUserActivePermissionKeys(ctx context.Context, companyUserID string) ([]string, error) {
        const query = `
                SELECT p.key 
                FROM company_user_permissions cup
                JOIN permissions p ON cup.permission_id = p.id
                WHERE cup.company_user_id = $1 AND cup.is_active = true
                ORDER BY p.module, p.key
        `

        rows, err := r.db.Query(ctx, query, companyUserID)
        if err != nil {
                return nil, fmt.Errorf("failed to get user permission keys: %w", err)
        }
        defer rows.Close()

        var keys []string
        for rows.Next() {
                var key string
                if err := rows.Scan(&key); err != nil {
                        return nil, fmt.Errorf("failed to scan permission key: %w", err)
                }
                keys = append(keys, key)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating permission keys: %w", err)
        }

        return keys, nil
}

// BatchGrant grants multiple permissions at once
func (r *CompanyUserPermissionRepository) BatchGrant(
        ctx context.Context,
        companyUserID string,
        permissionKeys []string,
        grantedBy string,
        notes string,
) ([]models.CompanyUserPermission, error) {
        // Use transaction for batch operation
        tx, err := r.db.Begin(ctx)
        if err != nil {
                return nil, fmt.Errorf("failed to begin transaction: %w", err)
        }
        
        defer func() {
                if err != nil {
                        tx.Rollback(ctx)
                }
        }()

        var permissions []models.CompanyUserPermission
        
        for _, key := range permissionKeys {
                const query = `
                        INSERT INTO company_user_permissions (company_user_id, permission_id, granted_by, notes)
                        SELECT $1, p.id, $2, $3
                        FROM permissions p
                        WHERE p.key = $4
                          AND NOT EXISTS (
                                SELECT 1 FROM company_user_permissions cup2
                                WHERE cup2.company_user_id = $1
                                  AND cup2.permission_id = p.id
                                  AND cup2.is_active = true
                          )
                        RETURNING 
                                id, company_user_id, permission_id,
                                granted_by, granted_at,
                                revoked_by, revoked_at, revocation_reason,
                                is_active, notes
                `
                
                row := tx.QueryRow(ctx, query, companyUserID, grantedBy, notes, key)
                
                var perm models.CompanyUserPermission
                var permissionID int
                err = row.Scan(
                        &perm.ID, &perm.CompanyUserID, &permissionID,
                        &perm.GrantedBy, &perm.GrantedAt,
                        &perm.RevokedBy, &perm.RevokedAt, &perm.RevocationReason,
                        &perm.IsActive, &perm.Notes,
                )
                
                if err != nil {
                        // Skip if already exists (not an error in batch)
                        continue
                }
                
                perm.PermissionKey = key
                permissions = append(permissions, perm)
        }
        
        // Commit transaction
        if err = tx.Commit(ctx); err != nil {
                return nil, fmt.Errorf("failed to commit batch grant: %w", err)
        }
        
        return permissions, nil
}

// RevokeAll revokes all permissions for a user (e.g., when deactivating)
func (r *CompanyUserPermissionRepository) RevokeAll(ctx context.Context, companyUserID string, revokedBy string) error {
        const query = `
                UPDATE company_user_permissions SET
                        revoked_by = $1,
                        revoked_at = NOW(),
                        revocation_reason = 'All permissions revoked',
                        is_active = false
                WHERE company_user_id = $2 AND is_active = true
        `

        _, err := r.db.Exec(ctx, query, revokedBy, companyUserID)
        if err != nil {
                return fmt.Errorf("failed to revoke all permissions: %w", err)
        }

        return nil
}

// GetUsersWithPermission returns all users who have a specific permission
func (r *CompanyUserPermissionRepository) GetUsersWithPermission(
        ctx context.Context,
        companyID string,
        permissionKey string,
        page, pageSize int,
) ([]models.CompanyUser, int64, error) {
        offset := (page - 1) * pageSize

        // Count query
        countQuery := `
                SELECT COUNT(DISTINCT cu.id)
                FROM company_users cu
                JOIN company_user_permissions cup ON cu.id = cup.company_user_id
                JOIN permissions p ON cup.permission_id = p.id
                WHERE cu.company_id = $1 
                  AND p.key = $2 
                  AND cu.deleted_at IS NULL
                  AND cup.is_active = true
        `
        var total int64
        err := r.db.QueryRow(ctx, countQuery, companyID, permissionKey).Scan(&total)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to count users with permission: %w", err)
        }

        // Data query
        dataQuery := `
                SELECT DISTINCT
                        cu.id, cu.company_id, cu.email,
                        cu.last_login_at, cu.login_attempts, cu.locked_until,
                        cu.password_changed_at, cu.must_change_password,
                        cu.first_name, cu.last_name, cu.display_name,
                        cu.avatar_url, cu.phone,
                        cu.role, cu.permission_version,
                        cu.is_active, cu.email_verified_at,
                        cu.preferences, cu.created_at, cu.updated_at, cu.deleted_at
                FROM company_users cu
                JOIN company_user_permissions cup ON cu.id = cup.company_user_id
                JOIN permissions p ON cup.permission_id = p.id
                WHERE cu.company_id = $1 
                  AND p.key = $2 
                  AND cu.deleted_at IS NULL
                  AND cup.is_active = true
                ORDER BY cu.created_at DESC
                LIMIT $3 OFFSET $4
        `

        rows, err := r.db.Query(ctx, dataQuery, companyID, permissionKey, pageSize, offset)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to query users with permission: %w", err)
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
                        return nil, 0, fmt.Errorf("failed to scan user: %w", err)
                }
                users = append(users, u)
        }

        if err := rows.Err(); err != nil {
                return nil, 0, fmt.Errorf("error iterating users: %w", err)
        }

        return users, total, nil
}

// GetPermissionHistory returns audit history of permission changes for a user
func (r *CompanyUserPermissionRepository) GetPermissionHistory(
        ctx context.Context,
        companyUserID string,
        page, pageSize int,
) ([]models.CompanyUserPermission, int64, error) {
        offset := (page - 1) * pageSize

        // Count query
        countQuery := `SELECT COUNT(*) FROM company_user_permissions WHERE company_user_id = $1`
        var total int64
        err := r.db.QueryRow(ctx, countQuery, companyUserID).Scan(&total)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to count permission history: %w", err)
        }

        // Data query (includes revoked permissions for full history)
        dataQuery := `
                SELECT 
                        cup.id, cup.company_user_id, cup.permission_id,
                        p.key as permission_key, p.name as permission_name,
                        cup.granted_by, gu_granter.first_name || ' ' || gu_granter.last_name as granted_by_name,
                        cup.granted_at,
                        cup.revoked_by, cup.revoked_at, cup.revocation_reason,
                        cup.is_active, cup.notes
                FROM company_user_permissions cup
                JOIN permissions p ON cup.permission_id = p.id
                LEFT JOIN company_users gu_granter ON cup.granted_by = gu_granter.id
                WHERE cup.company_user_id = $1
                ORDER BY cup.granted_at DESC
                LIMIT $2 OFFSET $3
        `

        rows, err := r.db.Query(ctx, dataQuery, companyUserID, pageSize, offset)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to query permission history: %w", err)
        }
        defer rows.Close()

        var permissions []models.CompanyUserPermission
        for rows.Next() {
                var perm models.CompanyUserPermission
                var permissionID int
                err := rows.Scan(
                        &perm.ID, &perm.CompanyUserID, &permissionID,
                        &perm.PermissionKey, &perm.PermissionName,
                        &perm.GrantedBy, &perm.GrantedByName,
                        &perm.GrantedAt,
                        &perm.RevokedBy, &perm.RevokedAt, &perm.RevocationReason,
                        &perm.IsActive, &perm.Notes,
                )
                if err != nil {
                        return nil, 0, fmt.Errorf("failed to scan permission history: %w", err)
                }
                permissions = append(permissions, perm)
        }

        if err := rows.Err(); err != nil {
                return nil, 0, fmt.Errorf("error iterating permission history: %w", err)
        }

        return permissions, total, nil
}

// GetGrantedByMe returns permissions that current user has granted to others
func (r *CompanyUserPermissionRepository) GetGrantedByMe(
        ctx context.Context,
        grantedBy string,
        page, pageSize int,
) ([]models.CompanyUserPermission, int64, error) {
        offset := (page - 1) * pageSize

        countQuery := `SELECT COUNT(*) FROM company_user_permissions WHERE granted_by = $1`
        var total int64
        err := r.db.QueryRow(ctx, countQuery, grantedBy).Scan(&total)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to count granted permissions: %w", err)
        }

        dataQuery := `
                SELECT 
                        cup.id, cup.company_user_id, cup.permission_id,
                        p.key as permission_key, p.name as permission_name,
                        cup.granted_by, gu_granter.first_name || ' ' || gu_granter.last_name as granted_by_name,
                        cup.granted_at,
                        cup.revoked_by, cup.revoked_at, cup.revocation_reason,
                        cup.is_active, cup.notes,
                        cu.first_name, cu.last_name, cu.email
                FROM company_user_permissions cup
                JOIN permissions p ON cup.permission_id = p.id
                LEFT JOIN company_users gu_granter ON cup.granted_by = gu_granter.id
                JOIN company_users cu ON cup.company_user_id = cu.id
                WHERE cup.granted_by = $1
                ORDER BY cup.granted_at DESC
                LIMIT $2 OFFSET $3
        `

        rows, err := r.db.Query(ctx, dataQuery, grantedBy, pageSize, offset)
        if err != nil {
                return nil, 0, fmt.Errorf("failed to query granted permissions: %w", err)
        }
        defer rows.Close()

        var permissions []models.CompanyUserPermission
        for rows.Next() {
                var perm models.CompanyUserPermission
                var permissionID int
                var targetFirstName, targetLastName, targetEmail string
                err := rows.Scan(
                        &perm.ID, &perm.CompanyUserID, &permissionID,
                        &perm.PermissionKey, &perm.PermissionName,
                        &perm.GrantedBy, &perm.GrantedByName,
                        &perm.GrantedAt,
                        &perm.RevokedBy, &perm.RevokedAt, &perm.RevocationReason,
                        &perm.IsActive, &perm.Notes,
                        &targetFirstName, &targetLastName, &targetEmail,
                )
                if err != nil {
                        return nil, 0, fmt.Errorf("scan error: %w", err)
                }
                permissions = append(permissions, perm)
        }

        if err := rows.Err(); err != nil {
                return nil, 0, fmt.Errorf("iterating error: %w", err)
        }

        return permissions, total, nil
}
