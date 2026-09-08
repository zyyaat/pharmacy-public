-- Migration: Permissions System & Authentication Integration
-- Version: Phase 1 - Revised Architecture
-- Description: Creates the dynamic permissions system with:
--              - Permissions catalog (all available permissions)
--              - Role templates (default permission sets)
--              - Employee permissions (SOURCE OF TRUTH for authorization)
--              - Functions for permission checking

-- ============================================
-- TABLE: permissions
-- Description: Catalog of all available permissions in the system
--              This is the master list - permissions are defined here once
-- ============================================
CREATE TABLE permissions (
    id SERIAL PRIMARY KEY,
    
    -- Permission Identification
    key VARCHAR(100) UNIQUE NOT NULL, -- e.g., 'employees.create', 'inventory.adjust'
    name VARCHAR(255) NOT NULL, -- Human-readable name (e.g., 'Create Employees')
    description TEXT,
    
    -- Categorization
    module VARCHAR(50) NOT NULL, -- e.g., 'employees', 'inventory', 'sales', 'reports'
    category VARCHAR(50), -- e.g., 'read', 'write', 'delete', 'admin'
    
    -- Hierarchy & Grouping
    parent_key VARCHAR(100) REFERENCES permissions(key), -- Parent permission (for grouping)
    is_system BOOLEAN DEFAULT false, -- System permissions cannot be deleted
    
    -- Metadata
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT permissions_valid_key_format CHECK (
        key ~ '^[a-z][a-z_]*(\.[a-z_]+)+$' -- Format: module.action or module.area.action
    )
);

-- Indexes for permissions
CREATE INDEX idx_permissions_module ON permissions(module);
CREATE INDEX idx_permissions_category ON permissions(category);
CREATE INDEX idx_permissions_key ON permissions(key);

COMMENT ON TABLE permissions IS 'Master catalog of all available permissions in the system';
COMMENT ON COLUMN permissions.key IS 'Permission identifier in format: module.action (e.g., employees.create)';
COMMENT ON COLUMN permissions.is_system IS 'System permissions cannot be deleted via API';

-- ============================================
-- Seed Data: Initial Permissions
-- Description: Core permissions for Phase 1 modules
-- ============================================
INSERT INTO permissions (key, name, description, module, category, is_system, sort_order) VALUES
-- Employees Module
('employees.view', 'View Employees', 'Can view employee list and details', 'employees', 'read', true, 1),
('employees.create', 'Create Employees', 'Can add new employees to the pharmacy', 'employees', 'write', true, 2),
('employees.update', 'Update Employees', 'Can edit employee information', 'employees', 'write', true, 3),
('employees.delete', 'Delete Employees', 'Can remove employees from the system', 'employees', 'delete', true, 4),
('employees.manage_permissions', 'Manage Employee Permissions', 'Can grant/revoke permissions to other employees', 'employees', 'admin', true, 5),

-- Inventory Module
('inventory.view', 'View Inventory', 'Can view inventory levels and details', 'inventory', 'read', true, 10),
('inventory.adjust', 'Adjust Inventory', 'Can make stock adjustments (increase/decrease)', 'inventory', 'write', true, 11),
('inventory.receive', 'Receive Goods', 'Can receive goods into inventory (create batches)', 'inventory', 'write', true, 12),
('inventory.transfer', 'Transfer Stock', 'Can transfer stock between branches', 'inventory', 'write', true, 13),
('inventory.writeoff', 'Write Off Stock', 'Can write off expired or damaged stock', 'inventory', 'delete', true, 14),
('inventory.manage_products', 'Manage Products', 'Can add/edit products from global catalog', 'inventory', 'admin', true, 15),

-- Products Module (Global Catalog - Admin only)
('products.global.manage', 'Manage Global Products', 'Can add/edit products in the global catalog (System Admin only)', 'products', 'admin', true, 20),
('products.pharmacy.add', 'Add Pharmacy Products', 'Can add products from global catalog to pharmacy', 'products', 'write', true, 21),
('products.pharmacy.pricing', 'Set Product Pricing', 'Can set selling prices and costs for pharmacy products', 'products', 'write', true, 22),

-- Branches Module
('branches.view', 'View Branches', 'Can view branch information', 'branches', 'read', true, 30),
('branches.create', 'Create Branches', 'Can create new branches', 'branches', 'write', true, 31),
('branches.update', 'Update Branches', 'Can edit branch information', 'branches', 'write', true, 32),
('branches.delete', 'Delete Branches', 'Can delete branches', 'branches', 'delete', true, 33),

-- Reports Module
('reports.inventory', 'Inventory Reports', 'Can view inventory reports and analytics', 'reports', 'read', true, 40),
('reports.sales', 'Sales Reports', 'Can view sales reports and analytics', 'reports', 'read', true, 41),
('reports.employees', 'Employee Reports', 'Can view employee reports and attendance', 'reports', 'read', true, 42),
('reports.financial', 'Financial Reports', 'Can view financial reports (P&L, etc.)', 'reports', 'read', true, 43),

-- Settings Module
('settings.general', 'General Settings', 'Can manage general pharmacy settings', 'settings', 'admin', true, 50),
('settings.billing', 'Billing Settings', 'Can manage billing and subscription settings', 'settings', 'admin', true, 51),
('settings.integrations', 'Integration Settings', 'Can manage third-party integrations', 'settings', 'admin', true, 52),

-- Attendance Module
('attendance.view', 'View Attendance', 'Can view attendance records', 'attendance', 'read', true, 60),
('attendance.clock_in_out', 'Clock In/Out', 'Can clock in and out', 'attendance', 'write', true, 61),
('attendance.manage', 'Manage Attendance', 'Can edit attendance records (admin function)', 'attendance', 'admin', true, 62),

-- Account/Pharmacy Admin
('pharmacy.admin', 'Pharmacy Administrator', 'Full administrative access to pharmacy (implies most permissions)', 'pharmacy', 'admin', true, 99)
ON CONFLICT (key) DO NOTHING;

-- ============================================
-- TABLE: roles
-- Description: Role templates - default permission sets
--              Roles are convenience groupings, NOT the source of truth for auth
-- ============================================
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Role Definition
    name VARCHAR(100) UNIQUE NOT NULL, -- e.g., 'Pharmacy Admin', 'Pharmacist'
    display_name VARCHAR(255), -- e.g., 'صيدلي', 'كاشير'
    description TEXT,
    
    -- Role Type
    is_system BOOLEAN DEFAULT false, -- System roles cannot be deleted
    is_default BOOLEAN DEFAULT false, -- Default role for new employees
    
    -- Scope
    account_id UUID REFERENCES accounts(id), -- NULL = system-wide role, else account-specific
    
    -- Status & Ordering
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for roles
CREATE INDEX idx_roles_name ON roles(name);
CREATE INDEX idx_roles_account ON roles(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX idx_roles_active ON roles(is_active) WHERE is_active = true;

-- RLS for roles (account-specific roles are isolated)
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "system_roles_visible_to_all" ON roles
    FOR SELECT USING (account_id IS NULL OR account_id = current_setting('app.current_account_id', true)::UUID);

COMMENT ON TABLE roles IS 'Role templates - default permission sets for convenience. NOT the source of truth for authorization.';
COMMENT ON COLUMN roles.account_id IS 'NULL = system role (available to all accounts), otherwise account-specific';

-- ============================================
-- Seed Data: Default System Roles
-- ============================================
INSERT INTO roles (id, name, display_name, description, is_system, is_default, sort_order) VALUES
('00000000-0000-0000-0000-000000000001', 'pharmacy_admin', 'Pharmacy Admin / مدير الصيدلية', 'Full access to all pharmacy features including user management', true, false, 1),
('00000000-0000-0000-0000-000000000002', 'pharmacist', 'Pharmacist / صيدلي', 'Can manage inventory, process sales, view reports', true, true, 2),
('00000000-0000-0000-0000-000000000003', 'cashier', 'Cashier / كاشير', 'Can process sales and view basic inventory', true, true, 3),
('00000000-0000-0000-0000-000000000004', 'inventory_manager', 'Inventory Manager / مسؤول المخزون', 'Full inventory management including adjustments and transfers', true, false, 4),
('00000000-0000-0000-0000-000000000005', 'hr_manager', 'HR Manager / مسؤول الموارد البشرية', 'Can manage employees and their permissions', true, false, 5)
ON CONFLICT (name) DO NOTHING;

-- ============================================
-- TABLE: role_permissions
-- Description: Default permission assignments for roles
--              These are TEMPLATES only - actual permissions come from employee_permissions
-- ============================================
CREATE TABLE role_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Relationships
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    
    -- Metadata
    granted_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT role_permissions_unique UNIQUE (role_id, permission_id)
);

-- Indexes for role_permissions
CREATE INDEX idx_role_permissions_role ON role_permissions(role_id);
CREATE INDEX idx_role_permissions_permission ON role_permissions(permission_id);

COMMENT ON TABLE role_permissions IS 'Default permission assignments for roles - used as template when assigning role to employee';

-- ============================================
-- Seed Data: Role Permission Assignments
-- ============================================
-- Pharmacy Admin - Gets almost everything
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    '00000000-0000-0000-0000-000000000001'::UUID,
    id 
FROM permissions 
WHERE key != 'products.global.manage' -- Global product management is system-admin only
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Pharmacist - Inventory + Sales + Basic Reports
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    '00000000-0000-0000-0000-000000000002'::UUID,
    id 
FROM permissions 
WHERE key IN (
    'employees.view',
    'inventory.view', 'inventory.adjust', 'inventory.receive', 'inventory.transfer',
    'products.pharmacy.add', 'products.pharmacy.pricing',
    'branches.view',
    'reports.inventory', 'reports.sales',
    'attendance.view', 'attendance.clock_in_out',
    'settings.general'
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Cashier - Sales only
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    '00000000-0000-0000-0000-000000000003'::UUID,
    id 
FROM permissions 
WHERE key IN (
    'employees.view',
    'inventory.view',
    'branches.view',
    'reports.sales',
    'attendance.clock_in_out'
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Inventory Manager - Full inventory control
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    '00000000-0000-0000-0000-000000000004'::UUID,
    id 
FROM permissions 
WHERE key IN (
    'employees.view',
    'inventory.view', 'inventory.adjust', 'inventory.receive', 'inventory.transfer', 'inventory.writeoff',
    'products.pharmacy.add', 'products.pharmacy.pricing',
    'branches.view',
    'reports.inventory',
    'attendance.view', 'attendance.clock_in_out'
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- HR Manager - Employee management
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    '00000000-0000-0000-0000-000000000005'::UUID,
    id 
FROM permissions 
WHERE key IN (
    'employees.view', 'employees.create', 'employees.update', 'employees.manage_permissions',
    'attendance.view', 'attendance.manage',
    'reports.employees'
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ============================================
-- TABLE: employee_permissions ⭐ SOURCE OF TRUTH ⭐
-- Description: Actual permissions granted to each employee
--              This is THE table that determines what an employee can do
--              Overrides any role-based permissions
-- ============================================
CREATE TABLE employee_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Relationships
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    
    -- Granting Information
    granted_by UUID NOT NULL REFERENCES employees(id), -- Who granted this permission
    granted_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    -- Revocation (soft delete - keeps history)
    revoked_by UUID REFERENCES employees(id), -- Who revoked this permission
    revoked_at TIMESTAMPTZ, -- NULL means still active
    revocation_reason TEXT,
    
    -- Status
    is_active BOOLEAN GENERATED ALWAYS AS (revoked_at IS NULL) STORED,
    
    -- Metadata
    notes TEXT -- Why was this granted? (for audit trail)
);

-- Indexes for employee_permissions (CRITICAL for performance)
CREATE UNIQUE INDEX idx_employee_permissions_unique_active
    ON employee_permissions(employee_id, permission_id)
    WHERE revoked_at IS NULL;
CREATE INDEX idx_employee_permissions_employee ON employee_permissions(employee_id) WHERE is_active = true;
CREATE INDEX idx_employee_permissions_permission ON employee_permissions(permission_id) WHERE is_active = true;
CREATE INDEX idx_employee_permissions_employee_active ON employee_permissions(employee_id, is_active) WHERE is_active = true;
CREATE INDEX idx_employee_permissions_granted_by ON employee_permissions(granted_by);

-- RLS for employee_permissions
ALTER TABLE employee_permissions ENABLE ROW LEVEL SECURITY;

-- Policy: Can view permissions for employees in same pharmacy
CREATE POLICY "can_view_same_pharmacy_permissions" ON employee_permissions
    FOR SELECT USING (
        employee_id IN (
            SELECT id FROM employees 
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

-- Policy: Can grant permissions if you have employees.manage_permissions
-- (This will be enforced at application level too)
CREATE POLICY "can_grant_same_pharmacy_permissions" ON employee_permissions
    FOR INSERT WITH CHECK (
        employee_id IN (
            SELECT id FROM employees 
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

-- Policy: Can revoke permissions you granted (or if you're admin)
CREATE POLICY "can_revoke_permissions" ON employee_permissions
    FOR UPDATE USING (
        employee_id IN (
            SELECT id FROM employees 
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

COMMENT ON TABLE employee_permissions IS '⭐ SOURCE OF TRUTH ⭐ - Actual permissions for each employee. This table determines authorization.';
COMMENT ON COLUMN employee_permissions.is_active IS 'Computed: true if not revoked. Use this for fast lookups.';
COMMENT ON COLUMN employee_permissions.revoked_at IS 'Soft delete - keeps full audit history';

-- ============================================
-- FUNCTION: Check if employee has a specific permission
-- ============================================
CREATE OR REPLACE FUNCTION has_permission(
    p_employee_id UUID,
    p_permission_key VARCHAR(100)
) RETURNS BOOLEAN AS $$
DECLARE
    v_has_perm BOOLEAN;
    v_permission_id INTEGER;
BEGIN
    -- Get permission ID
    SELECT id INTO v_permission_id FROM permissions WHERE key = p_permission_key;
    
    IF v_permission_id IS NULL THEN
        -- Permission doesn't exist
        RETURN FALSE;
    END IF;
    
    -- Check active permission
    SELECT TRUE INTO v_has_perm
    FROM employee_permissions
    WHERE employee_id = p_employee_id
      AND permission_id = v_permission_id
      AND is_active = true
    LIMIT 1;
    
    RETURN COALESCE(v_has_perm, FALSE);
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- FUNCTION: Get all active permissions for an employee
-- Returns: Array of permission keys
-- ============================================
CREATE OR REPLACE FUNCTION get_employee_permissions(p_employee_id UUID)
returns VARCHAR(100)[] AS $$
DECLARE
    v_permissions VARCHAR(100)[];
BEGIN
    SELECT ARRAY_AGG(p.key) INTO v_permissions
    FROM employee_permissions ep
    JOIN permissions p ON ep.permission_id = p.id
    WHERE ep.employee_id = p_employee_id
      AND ep.is_active = true;
    
    RETURN COALESCE(v_permissions, ARRAY[]::VARCHAR(100)[]);
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- FUNCTION: Increment employee permission version
-- Call this whenever permissions change for an employee
-- This invalidates cached JWT permission data
-- ============================================
CREATE OR REPLACE FUNCTION increment_employee_permission_version(p_employee_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_new_version INTEGER;
BEGIN
    UPDATE employees 
    SET permission_version = permission_version + 1,
        updated_at = NOW()
    WHERE id = p_employee_id
    RETURNING permission_version INTO v_new_version;
    
    RETURN COALESCE(v_new_version, 0);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGER: Auto-increment permission version on permission change
-- ============================================
CREATE OR REPLACE FUNCTION trigger_increment_permission_version()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM increment_permission_version(NEW.employee_id);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Only if revocation status changed
        IF NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
            PERFORM increment_permission_version(NEW.employee_id);
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_permission_version_change
AFTER INSERT OR UPDATE ON employee_permissions
FOR EACH ROW EXECUTE FUNCTION trigger_increment_permission_version();

-- ============================================
-- FUNCTION: Grant permission to employee (with proper validation)
-- ============================================
CREATE OR REPLACE FUNCTION grant_permission_to_employee(
    p_employee_id UUID,
    p_permission_key VARCHAR(100),
    p_granted_by UUID,
    p_notes TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_permission_id INTEGER;
    v_new_permission_id UUID;
    v_grantee_pharmacy_id UUID;
    v_granter_pharmacy_id UUID;
BEGIN
    -- Validate permission exists
    SELECT id INTO v_permission_id FROM permissions WHERE key = p_permission_key;
    IF v_permission_id IS NULL THEN
        RAISE EXCEPTION 'Permission does not exist: %', p_permission_key;
    END IF;
    
    -- Validate both employees exist and are in same pharmacy
    SELECT pharmacy_id INTO v_grantee_pharmacy_id FROM employees WHERE id = p_employee_id;
    SELECT pharmacy_id INTO v_granter_pharmacy_id FROM employees WHERE id = p_granted_by;
    
    IF v_grantee_pharmacy_id IS NULL THEN
        RAISE EXCEPTION 'Employee not found: %', p_employee_id;
    END IF;
    
    IF v_granter_pharmacy_id IS NULL THEN
        RAISE EXCEPTION 'Granting employee not found: %', p_granted_by;
    END IF;
    
    IF v_grantee_pharmacy_id != v_granter_pharmacy_id THEN
        RAISE EXCEPTION 'Cannot grant permissions across pharmacies';
    END IF;
    
    -- Check if already granted (and still active)
    IF EXISTS (
        SELECT 1 FROM employee_permissions 
        WHERE employee_id = p_employee_id 
          AND permission_id = v_permission_id 
          AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Employee already has this permission';
    END IF;
    
    -- Insert the permission (trigger will auto-increment version)
    INSERT INTO employee_permissions (employee_id, permission_id, granted_by, notes)
    VALUES (p_employee_id, v_permission_id, p_granted_by, p_notes)
    RETURNING id INTO v_new_permission_id;
    
    RETURN v_new_permission_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Revoke permission from employee (soft delete)
-- ============================================
CREATE OR REPLACE FUNCTION revoke_permission_from_employee(
    p_employee_id UUID,
    p_permission_key VARCHAR(100),
    p_revoked_by UUID,
    p_reason TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_permission_id INTEGER;
    v_updated BOOLEAN;
BEGIN
    -- Validate permission exists
    SELECT id INTO v_permission_id FROM permissions WHERE key = p_permission_key;
    IF v_permission_id IS NULL THEN
        RAISE EXCEPTION 'Permission does not exist: %', p_permission_key;
    END IF;
    
    -- Soft-delete the permission (set revoked_at)
    UPDATE employee_permissions
    SET 
        revoked_by = p_revoked_by,
        revoked_at = NOW(),
        revocation_reason = p_reason,
        is_active = false
    WHERE employee_id = p_employee_id
      AND permission_id = v_permission_id
      AND is_active = true; -- Only revoke active permissions
    
    -- Check if anything was updated
    v_updated := FOUND;
    
    IF NOT v_updated THEN
        RAISE EXCEPTION 'Active permission not found for this employee';
    END IF;
    
    -- Note: Trigger will auto-increment permission version
    
    RETURN v_updated;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- Updated triggers
-- ============================================
CREATE TRIGGER update_roles_updated_at BEFORE UPDATE ON roles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
