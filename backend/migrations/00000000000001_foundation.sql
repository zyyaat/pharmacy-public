-- Migration: Foundation Schema - Accounts, Tenancy, and Core Entities
-- Version: Phase 1 - Revised Architecture
-- Description: Creates the foundation tables for multi-tenant pharmacy management
--              Supports both single-pharmacy and multi-branch/company structures

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================
-- ENUM TYPES
-- ============================================
CREATE TYPE account_status AS ENUM ('active', 'suspended', 'cancelled', 'trial');
CREATE TYPE currency_code AS ENUM ('USD', 'EUR', 'GBP', 'EGP', 'SAR', 'AED', 'QAR', 'KWD', 'BHD', 'OMR', 'JOD', 'LBP', 'SYP', 'IQD', 'LYD', 'DZD', 'TND', 'MAD', 'YER');
CREATE TYPE employee_status AS ENUM ('active', 'inactive', 'on_leave', 'terminated');

-- ============================================
-- TABLE: accounts
-- Description: Top-level tenant account (pays the bill)
--              A single pharmacy = 1 account
--              A company with multiple pharmacies = 1 account
-- ============================================
CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Account Information
    company_name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255) UNIQUE NOT NULL,
    contact_phone VARCHAR(50),
    billing_address TEXT,
    
    -- Account Status & Subscription
    status account_status DEFAULT 'trial',
    trial_ends_at TIMESTAMPTZ,
    subscription_plan VARCHAR(50) DEFAULT 'free', -- free, professional, enterprise
    subscription_current_period_start TIMESTAMPTZ,
    subscription_current_period_end TIMESTAMPTZ,
    
    -- Settings
    default_currency currency_code DEFAULT 'USD',
    timezone VARCHAR(100) DEFAULT 'UTC',
    locale VARCHAR(10) DEFAULT 'en-US',
    settings JSONB DEFAULT '{}',
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for account lookups
CREATE INDEX idx_accounts_contact_email ON accounts(contact_email);
CREATE INDEX idx_accounts_status ON accounts(status);

-- ============================================
-- TABLE: pharmacies
-- Description: Individual pharmacy or main branch
--              Each pharmacy belongs to one account
-- ============================================
CREATE TABLE pharmacies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Tenant Relationship
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    
    -- Pharmacy Information
    name VARCHAR(255) NOT NULL,
    legal_name VARCHAR(255),
    license_number VARCHAR(100) UNIQUE,
    tax_id VARCHAR(100),
    
    -- Contact Information
    email VARCHAR(255),
    phone VARCHAR(50),
    website VARCHAR(255),
    
    -- Address
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(100) DEFAULT 'US',
    
    -- Configuration
    is_main_branch BOOLEAN DEFAULT true, -- True for single-pharmacy or HQ
    default_branch_id UUID, -- Will be set after branch creation
    currency currency_code, -- Inherits from account if NULL
    
    -- Operational Settings
    auto_expiry_alert_days INTEGER DEFAULT 90,
    low_stock_threshold INTEGER DEFAULT 10,
    enable_batch_tracking BOOLEAN DEFAULT true,
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for pharmacies
CREATE UNIQUE INDEX idx_pharmacies_license_number ON pharmacies(license_number) WHERE license_number IS NOT NULL;
CREATE INDEX idx_pharmacies_account_id ON pharmacies(account_id);
CREATE INDEX idx_pharmacies_active ON pharmacies(is_active) WHERE is_active = true;

-- RLS for pharmacies (System-level access for now, will be refined)
ALTER TABLE pharmacies ENABLE ROW LEVEL SECURITY;

-- Policy: Accounts can see their own pharmacies
CREATE POLICY "accounts_can_view_own_pharmacies" ON pharmacies
    FOR SELECT USING (
        account_id IN (
            SELECT id FROM accounts 
            WHERE id = pharmacies.account_id
        )
    );

-- ============================================
-- TABLE: branches
-- Description: Sub-branches of a pharmacy (optional)
--              Single-pharmacy setups don't need this table
-- ============================================
CREATE TABLE branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Parent Relationship
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    
    -- Branch Information
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50), -- Internal branch code (e.g., "BR-001")
    
    -- Contact Information
    phone VARCHAR(50),
    email VARCHAR(255),
    
    -- Address
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(100),
    
    -- Management
    manager_employee_id UUID, -- Will reference employees after table creation
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for branches
CREATE INDEX idx_branches_pharmacy_id ON branches(pharmacy_id);
CREATE INDEX idx_branches_active ON branches(is_active) WHERE is_active = true;
CREATE UNIQUE INDEX idx_branches_code_pharmacy ON branches(code, pharmacy_id) WHERE code IS NOT NULL;

-- Add foreign key constraint for manager (deferred because employees table doesn't exist yet)
-- This will be added in a later ALTER TABLE or next migration

-- RLS for branches
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

-- Policy: Pharmacies can see their own branches (via pharmacy_id)
CREATE POLICY "pharmacies_can_view_own_branches" ON branches
    FOR ALL USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

-- ============================================
-- TABLE: employees
-- Description: Staff members working at pharmacies/branches
--              Authentication is handled by the Go API.
-- ============================================
CREATE TABLE employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Tenant Relationships
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    
    -- Legacy provider identifier retained for data compatibility.
    auth_user_id UUID UNIQUE,
    email VARCHAR(255) NOT NULL,
    
    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    display_name VARCHAR(200), -- Preferred display name
    
    -- Contact Information
    phone VARCHAR(50),
    address TEXT,
    emergency_contact_name VARCHAR(100),
    emergency_contact_phone VARCHAR(50),
    
    -- Employment Information
    employee_id_internal VARCHAR(50), -- Internal employee number (e.g., "EMP-001")
    job_title VARCHAR(100),
    department VARCHAR(100),
    hire_date DATE,
    termination_date DATE,
    base_salary NUMERIC(12,2),
    
    -- Status & Permissions
    status employee_status DEFAULT 'active',
    permission_version INTEGER DEFAULT 0, -- Incremented when permissions change (for JWT cache invalidation)
    
    -- Profile Settings
    avatar_url TEXT,
    preferences JSONB DEFAULT '{}', -- UI preferences, notifications, etc.
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT employees_unique_email_per_pharmacy UNIQUE (email, pharmacy_id)
);

-- Indexes for employees
CREATE INDEX idx_employees_account_id ON employees(account_id);
CREATE INDEX idx_employees_pharmacy_id ON employees(pharmacy_id);
CREATE INDEX idx_employees_branch_id ON employees(branch_id) WHERE branch_id IS NOT NULL;
CREATE INDEX idx_employees_auth_user_id ON employees(auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE INDEX idx_employees_status ON employees(status);
CREATE INDEX idx_employees_email ON employees(email);

-- RLS for employees
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

-- Policy: Pharmacies can manage their own employees
CREATE POLICY "pharmacies_can_manage_own_employees" ON employees
    FOR ALL USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

-- ============================================
-- FUNCTION: Update updated_at timestamp
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at on all foundation tables
CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    
CREATE TRIGGER update_pharmacies_updated_at BEFORE UPDATE ON pharmacies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    
CREATE TRIGGER update_branches_updated_at BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    
CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- FUNCTION: Get or create default branch for pharmacy
-- ============================================
CREATE OR REPLACE FUNCTION get_or_create_default_branch(p_pharmacy_id UUID)
RETURNS UUID AS $$
DECLARE
    v_branch_id UUID;
    v_pharmacy_name VARCHAR(255);
BEGIN
    -- Try to get existing default branch
    SELECT id INTO v_branch_id FROM branches 
    WHERE pharmacy_id = p_pharmacy_id AND is_main_branch = true
    LIMIT 1;
    
    IF v_branch_id IS NOT NULL THEN
        RETURN v_branch_id;
    END IF;
    
    -- Get pharmacy name for the branch
    SELECT name INTO v_pharmacy_name FROM pharmacies WHERE id = p_pharmacy_id;
    
    -- Create default branch (Main Branch)
    INSERT INTO branches (pharmacy_id, name, code, is_active)
    VALUES (p_pharmacy_id, v_pharmacy_name || ' - Main Branch', 'MAIN', true)
    RETURNING id INTO v_branch_id;
    
    -- Update pharmacy to point to this branch
    UPDATE pharmacies SET default_branch_id = v_branch_id WHERE id = p_pharmacy_id;
    
    RETURN v_branch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- COMMENTS (PostgreSQL style with --)
-- ============================================
COMMENT ON TABLE accounts IS 'Top-level tenant accounts - represents the paying customer';
COMMENT ON TABLE pharmacies IS 'Individual pharmacy locations belonging to an account';
COMMENT ON TABLE branches IS 'Optional sub-branches within a pharmacy for multi-location setups';
COMMENT ON TABLE employees IS 'Staff members - authentication handled by the Go API';

COMMENT ON COLUMN employees.auth_user_id IS 'Legacy authentication provider identifier; unused by the Go API';
COMMENT ON COLUMN employees.permission_version IS 'Incremented when permissions change - used for JWT cache invalidation';
COMMENT ON COLUMN pharmacies.is_main_branch IS 'True for single-pharmacy or headquarters in multi-branch setup';
