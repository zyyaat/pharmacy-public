-- Migration: Holding Company / SaaS Platform Schema
-- Version: Phase 2 - Multi-Tenant SaaS Architecture
-- Description: Creates the holding company layer that sits above pharmacy accounts
--              This enables the SaaS model where we (the platform) manage multiple companies
--
-- Hierarchy:
--   Company (Holding Company / SaaS Customer)
--     └── Account (Pharmacy Business) ← existing table
--           └── Pharmacy → Branches ← existing tables

-- ============================================
-- ENUM TYPES FOR COMPANY
-- ============================================
CREATE TYPE company_status AS ENUM ('active', 'suspended', 'trial', 'cancelled');
CREATE TYPE company_plan AS ENUM ('free', 'starter', 'professional', 'enterprise', 'custom');
CREATE TYPE company_user_role AS ENUM ('super_admin', 'company_admin', 'company_manager', 'company_viewer');

-- ============================================
-- TABLE: companies ⭐ NEW ⭐
-- Description: Holding companies / SaaS customers
--              Each company can have multiple pharmacy accounts
-- ============================================
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Company Information
    name VARCHAR(255) NOT NULL,
    name_ar VARCHAR(255), -- Arabic name for RTL support
    legal_name VARCHAR(255), -- Registered legal name
    registration_number VARCHAR(100), -- Commercial registration
    
    -- Contact Information
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50),
    website VARCHAR(255),
    
    -- Address (Company HQ)
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(100) DEFAULT 'EG', -- Default to Egypt
    
    -- Subscription & Billing
    status company_status DEFAULT 'trial',
    plan company_plan DEFAULT 'free',
    trial_ends_at TIMESTAMPTZ,
    subscription_current_period_start TIMESTAMPTZ,
    subscription_current_period_end TIMESTAMPTZ,
    max_accounts INTEGER DEFAULT 1, -- Max number of pharmacy accounts
    max_users_per_account INTEGER DEFAULT 10,
    
    -- Configuration
    default_currency VARCHAR(10) DEFAULT 'EGP',
    timezone VARCHAR(100) DEFAULT 'Africa/Cairo',
    locale VARCHAR(10) DEFAULT 'ar-EG',
    settings JSONB DEFAULT '{}',
    
    -- Branding (White-label options)
    logo_url TEXT,
    primary_color VARCHAR(7), -- Hex color
    secondary_color VARCHAR(7),
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Soft delete
    deleted_at TIMESTAMPTZ,
    is_active BOOLEAN GENERATED ALWAYS AS (deleted_at IS NULL) STORED
);

-- Indexes for companies
CREATE INDEX idx_companies_email ON companies(email);
CREATE INDEX idx_companies_status ON companies(status);
CREATE INDEX idx_companies_plan ON companies(plan);
CREATE INDEX idx_companies_active ON companies(is_active) WHERE is_active = true;
CREATE INDEX idx_companies_trial_end ON companies(trial_ends_at) WHERE trial_ends_at IS NOT NULL;

-- RLS for companies
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Policy: Super admins can see all companies
CREATE POLICY "super_admins_can_manage_companies" ON companies
    FOR ALL USING (
        current_setting('app.is_super_admin', true)::BOOLEAN = true
        OR id = current_setting('app.current_company_id', true)::UUID
    );

COMMENT ON TABLE companies IS '⭐ HOLDING COMPANY ⭐ - Top-level SaaS customer. Can own multiple pharmacy accounts.';
COMMENT ON COLUMN companies.max_accounts IS 'Maximum number of pharmacy accounts this company can create';
COMMENT ON COLUMN companies.settings IS 'JSONB for flexible configuration (features, integrations, etc.)';

-- ============================================
-- TABLE: company_users ⭐ NEW ⭐
-- Description: Users who manage the holding company (NOT pharmacy employees)
--              These are company-level administrators and managers
--              Uses CUSTOM AUTH (password_hash stored locally, NOT Supabase Auth)
-- ============================================
CREATE TABLE company_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Company Relationship
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    
    -- Authentication (Custom - NOT Supabase)
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL, -- bcrypt hash
    last_login_at TIMESTAMPTZ,
    login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMPTZ, -- Account lockout after failed attempts
    password_changed_at TIMESTAMPTZ DEFAULT NOW(),
    must_change_password BOOLEAN DEFAULT false,
    
    -- Profile Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    display_name VARCHAR(200),
    avatar_url TEXT,
    phone VARCHAR(50),
    
    -- Role & Permissions
    role company_user_role DEFAULT 'company_viewer',
    permission_version INTEGER DEFAULT 0, -- For cache invalidation (same pattern as employees)
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    email_verified_at TIMESTAMPTZ,
    email_verification_token VARCHAR(255),
    password_reset_token VARCHAR(255),
    password_reset_expires_at TIMESTAMPTZ,
    
    -- Preferences
    preferences JSONB DEFAULT '{}',
    
    -- Timestamps & Soft Delete
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    
    -- Constraints
    CONSTRAINT company_users_unique_email_per_company UNIQUE (email, company_id)
);

-- Indexes for company_users
CREATE INDEX idx_company_users_company_id ON company_users(company_id);
CREATE INDEX idx_company_users_email ON company_users(email);
CREATE INDEX idx_company_users_role ON company_users(role);
CREATE INDEX idx_company_users_active ON company_users(is_active) WHERE is_active = true;
CREATE INDEX idx_company_users_email_token ON company_users(email_verification_token) WHERE email_verification_token IS NOT NULL;
CREATE INDEX idx_company_users_password_reset ON company_users(password_reset_token) WHERE password_reset_token IS NOT NULL;

-- RLS for company_users
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;

-- Policy: Company users can see users in same company (if they have permissions)
CREATE POLICY "company_users_can_manage_same_company" ON company_users
    FOR ALL USING (
        company_id = current_setting('app.current_company_id', true)::UUID
    );

-- Policy: Super admins can manage all company users
CREATE POLICY "super_admins_can_manage_all_company_users" ON company_users
    FOR ALL USING (
        current_setting('app.is_super_admin', true)::BOOLEAN = true
    );

COMMENT ON TABLE company_users IS 'Company-level users with custom auth (bcrypt). These are NOT pharmacy employees.';
COMMENT ON COLUMN company_users.password_hash IS 'bcrypt hash - custom auth, NOT Supabase Auth';
COMMENT ON COLUMN company_users.permission_version IS 'Incremented on permission change - for JWT cache invalidation';

-- ============================================
-- TABLE: company_user_permissions ⭐ NEW ⭐
-- Description: SOURCE OF TRUTH for company user permissions
--              Same pattern as employee_permissions but for company level
-- ============================================
CREATE TABLE company_user_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Relationships
    company_user_id UUID NOT NULL REFERENCES company_users(id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE, -- Reuses existing permissions table!
    
    -- Granting Information
    granted_by UUID NOT NULL REFERENCES company_users(id), -- Who granted this
    granted_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    -- Revocation (soft delete)
    revoked_by UUID REFERENCES company_users(id),
    revoked_at TIMESTAMPTZ,
    revocation_reason TEXT,
    
    -- Status
    is_active BOOLEAN GENERATED ALWAYS AS (revoked_at IS NULL) STORED,
    
    -- Metadata
    notes TEXT
    
    -- Active rows are kept unique by the partial unique index below.
);

-- Indexes for company_user_permissions
CREATE UNIQUE INDEX company_user_perms_unique_active
    ON company_user_permissions(company_user_id, permission_id)
    WHERE revoked_at IS NULL;
CREATE INDEX idx_company_user_perms_user ON company_user_permissions(company_user_id) WHERE is_active = true;
CREATE INDEX idx_company_user_perms_permission ON company_user_permissions(permission_id) WHERE is_active = true;
CREATE INDEX idx_company_user_perms_granted_by ON company_user_permissions(granted_by);

-- RLS for company_user_permissions
ALTER TABLE company_user_permissions ENABLE ROW LEVEL SECURITY;

-- Policy: Can view permissions for same company users
CREATE POLICY "can_view_same_company_permissions" ON company_user_permissions
    FOR SELECT USING (
        company_user_id IN (
            SELECT id FROM company_users 
            WHERE company_id = current_setting('app.current_company_id', true)::UUID
        )
    );

COMMENT ON TABLE company_user_permissions IS '⭐ SOURCE OF TRUTH ⭐ - Company user permissions. Same pattern as employee_permissions.';

-- ============================================
-- MODIFY: Add company_id to accounts table
-- ============================================
ALTER TABLE accounts 
ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id) ON DELETE SET NULL;
ALTER TABLE accounts
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Update existing accounts to link to a default company (migration helper)
-- This allows existing data to work during transition
COMMENT ON COLUMN accounts.company_id IS 'Link to holding company. NULL for legacy/migrated accounts.';

-- Create index for company_id
CREATE INDEX IF NOT EXISTS idx_accounts_company_id ON accounts(company_id) WHERE company_id IS NOT NULL;

-- Update RLS policy for accounts to consider company
DROP POLICY IF EXISTS "accounts_can_view_own_accounts" ON accounts;
CREATE POLICY "accounts_can_view_own_accounts" ON accounts
    FOR ALL USING (
        company_id = current_setting('app.current_company_id', true)::UUID
        OR id = current_setting('app.current_account_id', true)::UUID
        OR current_setting('app.is_super_admin', true)::BOOLEAN = true
    );

-- ============================================
-- COMPANY-LEVEL PERMISSIONS (extend existing permissions)
-- ============================================

-- Add company-specific permissions if they don't exist
ALTER TABLE permissions DROP CONSTRAINT IF EXISTS permissions_valid_key_format;
ALTER TABLE permissions ADD CONSTRAINT permissions_valid_key_format CHECK (
    key ~ '^[a-z][a-z_]*(\.[a-z_]+)+$'
);

INSERT INTO permissions (key, name, description, module, category, is_system, sort_order) VALUES
-- Company Management
('companies.view', 'View Companies', 'Can view company information and details', 'companies', 'read', true, 70),
('companies.create', 'Create Companies', 'Can create new companies (Super Admin only)', 'companies', 'admin', true, 71),
('companies.update', 'Update Companies', 'Can update company information', 'companies', 'write', true, 72),
('companies.delete', 'Delete Companies', 'Can delete/suspend companies (Super Admin only)', 'companies', 'delete', true, 73),
('companies.manage_subscription', 'Manage Subscriptions', 'Can manage company subscriptions and billing', 'companies', 'admin', true, 74),

-- Company User Management
('company_users.view', 'View Company Users', 'Can view company user list', 'company_users', 'read', true, 80),
('company_users.create', 'Create Company Users', 'Can add new company users', 'company_users', 'write', true, 81),
('company_users.update', 'Update Company Users', 'Can edit company user information', 'company_users', 'write', true, 82),
('company_users.delete', 'Delete Company Users', 'Can remove company users', 'company_users', 'delete', true, 83),
('company_users.manage_permissions', 'Manage User Permissions', 'Can grant/revoke permissions to company users', 'company_users', 'admin', true, 84),

-- Account Management (under company)
('accounts.view', 'View Accounts', 'Can view pharmacy accounts under company', 'accounts', 'read', true, 90),
('accounts.create', 'Create Accounts', 'Can create new pharmacy accounts', 'accounts', 'write', true, 91),
('accounts.update', 'Update Accounts', 'Can edit account information', 'accounts', 'write', true, 92),
('accounts.delete', 'Delete Accounts', 'Can delete/suspend accounts', 'accounts', 'delete', true, 93),

-- Platform Admin (Super Admin only)
('platform.admin', 'Platform Administrator', 'Full platform administration access', 'platform', 'admin', true, 99),
('platform.analytics', 'View Platform Analytics', 'Can view platform-wide analytics', 'platform', 'read', true, 98),
('platform.audit', 'View Audit Logs', 'Can view system-wide audit logs', 'platform', 'read', true, 97)
ON CONFLICT (key) DO NOTHING;

-- ============================================
-- FUNCTIONS: Company Permission Management
-- ============================================

-- Function: Check if company user has permission
CREATE OR REPLACE FUNCTION has_company_permission(
    p_company_user_id UUID,
    p_permission_key VARCHAR(100)
) RETURNS BOOLEAN AS $$
DECLARE
    v_has_perm BOOLEAN;
    v_permission_id INTEGER;
BEGIN
    SELECT id INTO v_permission_id FROM permissions WHERE key = p_permission_key;
    
    IF v_permission_id IS NULL THEN
        RETURN FALSE;
    END IF;
    
    SELECT TRUE INTO v_has_perm
    FROM company_user_permissions
    WHERE company_user_id = p_company_user_id
      AND permission_id = v_permission_id
      AND is_active = true
    LIMIT 1;
    
    RETURN COALESCE(v_has_perm, FALSE);
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Get all permissions for a company user
CREATE OR REPLACE FUNCTION get_company_user_permissions(p_company_user_id UUID)
RETURNS VARCHAR(100)[] AS $$
DECLARE
    v_permissions VARCHAR(100)[];
BEGIN
    SELECT ARRAY_AGG(p.key) INTO v_permissions
    FROM company_user_permissions cup
    JOIN permissions p ON cup.permission_id = p.id
    WHERE cup.company_user_id = p_company_user_id
      AND cup.is_active = true;
    
    RETURN COALESCE(v_permissions, ARRAY[]::VARCHAR(100)[]);
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Increment company user permission version
CREATE OR REPLACE FUNCTION increment_company_user_permission_version(p_company_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_new_version INTEGER;
BEGIN
    UPDATE company_users 
    SET permission_version = permission_version + 1,
        updated_at = NOW()
    WHERE id = p_company_user_id
    RETURNING permission_version INTO v_new_version;
    
    RETURN COALESCE(v_new_version, 0);
END;
$$ LANGUAGE plpgsql;

-- Trigger: Auto-increment permission version on change
CREATE OR REPLACE FUNCTION trigger_company_permission_version_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM increment_company_user_permission_version(NEW.company_user_id);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
            PERFORM increment_company_user_permission_version(NEW.company_user_id);
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_company_permission_version
AFTER INSERT OR UPDATE ON company_user_permissions
FOR EACH ROW EXECUTE FUNCTION trigger_company_permission_version_change();

-- Function: Grant permission to company user
CREATE OR REPLACE FUNCTION grant_permission_to_company_user(
    p_company_user_id UUID,
    p_permission_key VARCHAR(100),
    p_granted_by UUID,
    p_notes TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_permission_id INTEGER;
    v_new_permission_id UUID;
    v_grantee_company_id UUID;
    v_granter_company_id UUID;
BEGIN
    SELECT id INTO v_permission_id FROM permissions WHERE key = p_permission_key;
    IF v_permission_id IS NULL THEN
        RAISE EXCEPTION 'Permission does not exist: %', p_permission_key;
    END IF;
    
    SELECT company_id INTO v_grantee_company_id FROM company_users WHERE id = p_company_user_id;
    SELECT company_id INTO v_granter_company_id FROM company_users WHERE id = p_granted_by;
    
    IF v_grantee_company_id IS NULL THEN
        RAISE EXCEPTION 'Company user not found: %', p_company_user_id;
    END IF;
    
    IF v_granter_company_id IS NULL THEN
        RAISE EXCEPTION 'Granting user not found: %', p_granted_by;
    END IF;
    
    IF v_grantee_company_id != v_granter_company_id THEN
        RAISE EXCEPTION 'Cannot grant permissions across companies';
    END IF;
    
    IF EXISTS (
        SELECT 1 FROM company_user_permissions 
        WHERE company_user_id = p_company_user_id 
          AND permission_id = v_permission_id 
          AND is_active = true
    ) THEN
        RAISE EXCEPTION 'User already has this permission';
    END IF;
    
    INSERT INTO company_user_permissions (company_user_id, permission_id, granted_by, notes)
    VALUES (p_company_user_id, v_permission_id, p_granted_by, p_notes)
    RETURNING id INTO v_new_permission_id;
    
    RETURN v_new_permission_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Revoke permission from company user
CREATE OR REPLACE FUNCTION revoke_permission_from_company_user(
    p_company_user_id UUID,
    p_permission_key VARCHAR(100),
    p_revoked_by UUID,
    p_reason TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_permission_id INTEGER;
    v_updated BOOLEAN;
BEGIN
    SELECT id INTO v_permission_id FROM permissions WHERE key = p_permission_key;
    IF v_permission_id IS NULL THEN
        RAISE EXCEPTION 'Permission does not exist: %', p_permission_key;
    END IF;
    
    UPDATE company_user_permissions
    SET 
        revoked_by = p_revoked_by,
        revoked_at = NOW(),
        revocation_reason = p_reason,
        is_active = false
    WHERE company_user_id = p_company_user_id
      AND permission_id = v_permission_id
      AND is_active = true;
    
    v_updated := FOUND;
    
    IF NOT v_updated THEN
        RAISE EXCEPTION 'Active permission not found for this user';
    END IF;
    
    RETURN v_updated;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- TRIGGERS: Updated at columns
-- ============================================
CREATE TRIGGER update_companies_updated_at BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    
CREATE TRIGGER update_company_users_updated_at BEFORE UPDATE ON company_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- VIEWS: Useful company-level views
-- ============================================

-- View: Company with account count
CREATE OR REPLACE VIEW v_company_summary AS
SELECT 
    c.*,
    COUNT(DISTINCT a.id) AS total_accounts,
    COUNT(DISTINCT CASE WHEN a.status = 'active' THEN a.id END) AS active_accounts,
    COUNT(DISTINCT cu.id) AS total_users
FROM companies c
LEFT JOIN accounts a ON a.company_id = c.id AND a.deleted_at IS NULL
LEFT JOIN company_users cu ON cu.company_id = c.id AND cu.deleted_at IS NULL AND cu.is_active = true
WHERE c.deleted_at IS NULL
GROUP BY c.id;

-- View: Company users with their permissions
CREATE OR REPLACE VIEW v_company_user_with_permissions AS
SELECT 
    cu.*,
    COALESCE(perm_count.permission_count, 0) AS total_permissions,
    ARRAY(
        SELECT p.key 
        FROM company_user_permissions cup2
        JOIN permissions p ON cup2.permission_id = p.id
        WHERE cup2.company_user_id = cu.id AND cup2.is_active = true
    ) AS permission_keys
FROM company_users cu
LEFT JOIN (
    SELECT company_user_id, COUNT(*) AS permission_count
    FROM company_user_permissions
    WHERE is_active = true
    GROUP BY company_user_id
) perm_count ON perm_count.company_user_id = cu.id
WHERE cu.deleted_at IS NULL;

-- ============================================
-- SEED DATA: Default super admin user (optional)
-- This creates a default super admin for initial setup
-- ============================================
-- Note: Password should be set via application, not here
-- INSERT INTO companies (name, email, plan, status) VALUES 
--     ('Pharmacy OS Platform', 'admin@pharmacy-os.com', 'enterprise', 'active');

-- ============================================
-- COMMENTS
-- ============================================
COMMENT ON SCHEMA public IS 'Pharmacy OS Database - Phase 2: Holding Company Layer Added';
COMMENT ON VIEW v_company_summary IS 'Company overview with account/user counts';
COMMENT ON VIEW v_company_user_with_permissions IS 'Company users with their permission details';
