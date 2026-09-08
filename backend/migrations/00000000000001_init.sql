-- Migration: Initial Schema for Pharmacy OS
-- This migration creates all base tables with RLS support

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create custom types
CREATE TYPE plan_type AS ENUM ('free', 'pro', 'enterprise');
CREATE TYPE employee_role AS ENUM ('admin', 'pharmacist', 'cashier', 'stockkeeper');

-- ============================================
-- TABLE: pharmacies (Tenant table)
-- ============================================
CREATE TABLE IF NOT EXISTS pharmacies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50),
    plan_type plan_type DEFAULT 'free',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABLE: branches
-- ============================================
CREATE TABLE IF NOT EXISTS branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    address TEXT NOT NULL,
    phone VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for branches
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Pharmacies can see their own branches" ON branches
    USING (pharmacy_id = current_setting('app.current_pharmacy_id', true)::uuid);

-- Indexes for branches
CREATE INDEX idx_branches_pharmacy_id ON branches(pharmacy_id);

-- ============================================
-- TABLE: employees
-- ============================================
CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    password_hash VARCHAR(255) NOT NULL,
    role employee_role DEFAULT 'cashier',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique email per pharmacy
CREATE UNIQUE INDEX idx_employees_email_pharmacy ON employees(email, pharmacy_id);

-- RLS for employees
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Pharmacies can see their own employees" ON employees
    USING (pharmacy_id = current_setting('app.current_pharmacy_id', true)::uuid);

-- ============================================
-- TABLE: medications (Inventory)
-- ============================================
CREATE TABLE IF NOT EXISTS medications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255),
    sku VARCHAR(100) NOT NULL,
    quantity INTEGER DEFAULT 0 CHECK (quantity >= 0),
    min_stock_level INTEGER DEFAULT 10,
    price DECIMAL(10,2) NOT NULL,
    expiry_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique SKU per pharmacy
CREATE UNIQUE INDEX idx_medications_sku_pharmacy ON medications(sku, pharmacy_id);

-- RLS for medications
ALTER TABLE medications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Pharmacies can see their own medications" ON medications
    USING (pharmacy_id = current_setting('app.current_pharmacy_id', true)::uuid);

-- Index for low stock queries
CREATE INDEX idx_medications_low_stock ON medications(pharmacy_id) WHERE quantity <= min_stock_level;

-- ============================================
-- TABLE: attendance_records (PARTITIONED)
-- Note: PK must be (id, clock_in) for partitioning
-- ============================================
CREATE TABLE IF NOT EXISTS attendance_records (
    id UUID NOT NULL,
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    clock_in TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    clock_out TIMESTAMPTZ,
    notes TEXT,
    PRIMARY KEY (id, clock_in)
) PARTITION BY RANGE (clock_in);

-- Create monthly partitions (example for current and next month)
-- Additional partitions should be created via scheduled job
CREATE TABLE attendance_records_2024_01 PARTITION OF attendance_records
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE attendance_records_2024_02 PARTITION OF attendance_records
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- Index on employee_id for lookups
CREATE INDEX idx_attendance_employee_id ON attendance_records(employee_id);

-- RLS for attendance_records
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;
-- Policy will join through employees table to check pharmacy_id

-- ============================================
-- TABLE: inventory_transfers
-- ============================================
CREATE TABLE IF NOT EXISTS inventory_transfers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    from_branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    to_branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    medication_id UUID NOT NULL REFERENCES medications(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'in_transit', 'completed', 'cancelled')),
    requested_by UUID REFERENCES employees(id),
    approved_by UUID REFERENCES employees(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- RLS for inventory_transfers
ALTER TABLE inventory_transfers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Pharmacies can see their own transfers" ON inventory_transfers
    USING (pharmacy_id = current_setting('app.current_pharmacy_id', true)::uuid);

-- ============================================
-- TABLE: audit_logs (No RLS - admin access only)
-- ============================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    action VARCHAR(100) NOT NULL,
    resource VARCHAR(100) NOT NULL,
    resource_id UUID,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for audit log queries
CREATE INDEX idx_audit_logs_pharmacy_id ON audit_logs(pharmacy_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);

-- ============================================
-- FUNCTION: Update updated_at timestamp
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at
CREATE TRIGGER update_pharmacies_updated_at BEFORE UPDATE ON pharmacies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_branches_updated_at BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_medications_updated_at BEFORE UPDATE ON medications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
