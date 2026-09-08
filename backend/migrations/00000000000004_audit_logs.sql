-- Migration: Audit Logs & Attendance System
-- Version: Phase 1 - Revised Architecture
-- Description: Creates comprehensive audit logging system and attendance tracking
--              - Audit logs with RLS for tenant isolation
-- - Attendance records (non-partitioned, optimized for current scale)

-- ============================================
-- TABLE: audit_logs
-- Description: Comprehensive audit trail of all system actions
--              Every important action should be logged here
--              Supports both automatic (triggers) and manual logging
-- ============================================
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Tenant Context (for RLS)
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    
    -- Actor Information (who performed the action)
    actor_id UUID REFERENCES employees(id), -- The employee who did it
    actor_email VARCHAR(255), -- Denormalized for quick queries
    actor_display_name VARCHAR(255), -- "John Doe" instead of just ID
    actor_role VARCHAR(100), -- Role at time of action (denormalized)
    actor_auth_user_id UUID, -- Supabase auth user ID
    
    -- Action Details (what happened)
    action VARCHAR(100) NOT NULL, -- 'employees.create', 'inventory.adjust', 'auth.login', etc.
    action_category VARCHAR(50), -- 'create', 'update', 'delete', 'login', 'logout', 'view', 'export'
    
    -- Entity Information (what was affected)
    entity_type VARCHAR(100) NOT NULL, -- Table name or resource type: 'employee', 'inventory_batch', etc.
    entity_id UUID, -- ID of the affected entity
    
    -- Data Changes (before and after)
    old_values JSONB, -- Snapshot of data BEFORE the change (for updates/deletes)
    new_values JSONB, -- Snapshot of data AFTER the change (for creates/updates)
    
    -- Change Summary (for quick viewing without parsing JSON)
    changes_summary TEXT, -- Human-readable summary: "Changed price from $10 to $12"
    fields_changed TEXT[], -- List of field names that changed
    
    -- Request Context (for security auditing)
    request_id VARCHAR(100), -- Correlation ID for tracing requests
    ip_address INET,
    user_agent TEXT,
    client_info JSONB, -- {platform, os, browser}
    
    -- Result & Impact
    success BOOLEAN DEFAULT true, -- Did the action succeed?
    error_message TEXT, -- If failed, why?
    duration_ms INTEGER, -- How long did the action take (for performance monitoring)
    
    -- Metadata
    severity VARCHAR(20) DEFAULT 'info', -- 'info', 'warning', 'critical'
    tags TEXT[], -- For categorization: ['sensitive', 'compliance', 'financial']
    notes TEXT, -- Additional context
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes for audit_logs (optimized for common query patterns)
CREATE INDEX idx_audit_logs_pharmacy_id ON audit_logs(pharmacy_id);
CREATE INDEX idx_audit_logs_account_id ON audit_logs(account_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id) WHERE entity_id IS NOT NULL;
CREATE INDEX idx_audit_logs_actor ON audit_logs(actor_id) WHERE actor_id IS NOT NULL;

-- Composite indexes for dashboard queries
CREATE INDEX idx_audit_logs_pharmacy_date ON audit_logs(pharmacy_id, created_at DESC);
CREATE INDEX idx_audit_logs_pharmacy_action ON audit_logs(pharmacy_id, action, created_at DESC);

-- The regular created_at index above supports date-range filtering.
-- A partial index based on NOW() would be invalid because NOW() is not immutable.

-- RLS for audit_logs - Critical for tenant isolation
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Policy: Pharmacies can only see their own audit logs
CREATE POLICY "pharmacies_can_view_own_audit_logs" ON audit_logs
    FOR SELECT USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

-- Policy: Only same-pharmacy employees can insert audit logs
CREATE POLICY "pharmacies_can_insert_own_audit_logs" ON audit_logs
    FOR INSERT WITH CHECK (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

-- Policy: No one can update or delete audit logs (immutable)
CREATE POLICY "audit_logs_immutable_no_update" ON audit_logs
    FOR UPDATE USING (false);

CREATE POLICY "audit_logs_immutable_no_delete" ON audit_logs
    FOR DELETE USING (false);

COMMENT ON TABLE audit_logs IS 'Comprehensive audit trail - immutable log of all system actions';
COMMENT ON COLUMN audit_logs.old_values IS 'JSON snapshot before change (for updates/deletes)';
COMMENT ON COLUMN audit_logs.new_values IS 'JSON snapshot after change (for creates/updates)';
COMMENT ON COLUMN audit_logs.severity IS 'Severity level: info, warning, critical';

-- ============================================
-- FUNCTION: Log audit entry (convenience function)
-- ============================================
CREATE OR REPLACE FUNCTION log_audit(
    p_pharmacy_id UUID,
    p_account_id UUID,
    p_actor_id UUID,
    p_action VARCHAR(100),
    p_entity_type VARCHAR(100),
    p_entity_id UUID DEFAULT NULL,
    p_old_values JSONB DEFAULT NULL,
    p_new_values JSONB DEFAULT NULL,
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_success BOOLEAN DEFAULT TRUE,
    p_severity VARCHAR(20) DEFAULT 'info'
) RETURNS UUID AS $$
DECLARE
    v_audit_id UUID;
    v_actor_email VARCHAR(255);
    v_actor_name VARCHAR(255);
BEGIN
    -- Get actor details (denormalize for performance)
    SELECT email, COALESCE(display_name, first_name || ' ' || last_name)
    INTO v_actor_email, v_actor_name
    FROM employees WHERE id = p_actor_id;
    
    -- Insert audit log
    INSERT INTO audit_logs (
        pharmacy_id, account_id, actor_id, actor_email, actor_display_name,
        action, entity_type, entity_id, old_values, new_values,
        ip_address, user_agent, success, severity
    ) VALUES (
        p_pharmacy_id, p_account_id, p_actor_id, v_actor_email, v_actor_name,
        p_action, p_entity_type, p_entity_id, p_old_values, p_new_values,
        p_ip_address, p_user_agent, p_success, p_severity
    ) RETURNING id INTO v_audit_id;
    
    RETURN v_audit_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- TABLE: attendance_records
-- Description: Employee attendance/clock-in clock-out records
--              Non-partitioned design (partitioning will be added when needed >5M records)
--              Optimized for current scale with proper indexes
-- ============================================
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE attendance_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Employee & Location
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE, -- Denormalized for fast queries
    
    -- Clock In/Out Times
    clock_in TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    clock_out TIMESTAMPTZ,
    
    -- Calculated Duration (in minutes)
    total_minutes INTEGER GENERATED ALWAYS AS (
        CASE 
            WHEN clock_out IS NOT NULL 
            THEN EXTRACT(EPOCH FROM (clock_out - clock_in)) / 60
            ELSE NULL 
        END
    ) STORED,
    
    -- Status
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'completed', 'adjusted', 'missed_clockout')),
    
    -- Notes & Adjustments
    notes TEXT,
    adjustment_reason TEXT, -- If times were manually adjusted
    adjusted_by UUID REFERENCES employees(id),
    adjusted_at TIMESTAMPTZ,
    
    -- Device/Location Data (for mobile apps)
    clock_in_ip INET,
    clock_in_location POINT, -- PostGIS point (longitude, latitude) if geo enabled
    clock_out_ip INET,
    clock_out_location POINT,
    device_info JSONB, -- {device_type: 'mobile', os: 'iOS', app_version: '1.2.0'}
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT no_overlapping_attendance EXCLUDE USING GIST (
        employee_id WITH =,
        tstzrange(clock_in, COALESCE(clock_out, 'infinity'::timestamptz)) WITH &&
    )
);

-- Note: The exclusion constraint above requires btree_gist extension
-- CREATE EXTENSION IF NOT EXISTS btree_gist; -- Add to first migration if needed

-- Indexes for attendance_records (optimized for common queries)
CREATE INDEX idx_attendance_employee_id ON attendance_records(employee_id);
CREATE INDEX idx_attendance_branch_id ON attendance_records(branch_id);
CREATE INDEX idx_attendance_pharmacy_id ON attendance_records(pharmacy_id);
CREATE INDEX idx_attendance_clock_in ON attendance_records(clock_in DESC);
CREATE INDEX idx_attendance_clock_out ON attendance_records(clock_out) WHERE clock_out IS NOT NULL;
CREATE INDEX idx_attendance_status ON attendance_records(status);
-- The regular clock_in index above supports date-range filtering.

-- Composite indexes for reporting
CREATE INDEX idx_attendance_employee_date ON attendance_records(employee_id, clock_in DESC);
CREATE INDEX idx_attendance_branch_date ON attendance_records(branch_id, clock_in DESC);
CREATE INDEX idx_attendance_pharmacy_date ON attendance_records(pharmacy_id, clock_in DESC);

-- Index for finding missed clock-outs (employees who clocked in but not out)
-- NOW() is not immutable, so this cannot be a partial index. The composite
-- status/clock_in index supports the same lookup without a time-dependent
-- predicate.
CREATE INDEX idx_attendance_status_clock_in ON attendance_records(status, clock_in);

-- RLS for attendance_records
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;

-- Policy: Pharmacies can see attendance for their employees
CREATE POLICY "pharmacies_can_view_own_attendance" ON attendance_records
    FOR SELECT USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

-- Policy: Can insert attendance for own pharmacy
CREATE POLICY "pharmacies_can_insert_own_attendance" ON attendance_records
    FOR INSERT WITH CHECK (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

-- Policy: Can update attendance (for adjustments) if you have attendance.manage permission
-- (Additional application-level check required)
CREATE POLICY "pharmacies_can_update_own_attendance" ON attendance_records
    FOR UPDATE USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

-- No delete policy (attendance records should not be deleted, only adjusted)

COMMENT ON TABLE attendance_records IS 'Employee attendance records - non-partitioned (add partitioning when >5M records)';
COMMENT ON COLUMN attendance_records.total_minutes IS 'Auto-calculated duration in minutes between clock_in and clock_out';
COMMENT ON COLUMN attendance_records.status IS 'active=clocked in, completed=clocked out, adjusted=manually changed, missed_clockout=forgot to clock out';

-- ============================================
-- FUNCTION: Clock in an employee
-- ============================================
CREATE OR REPLACE FUNCTION clock_in_employee(
    p_employee_id UUID,
    p_branch_id UUID,
    p_ip_address INET DEFAULT NULL,
    p_device_info JSONB DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_attendance_id UUID;
    v_pharmacy_id UUID;
    v_active_record INTEGER;
BEGIN
    -- Get pharmacy_id from branch
    SELECT pharmacy_id INTO v_pharmacy_id FROM branches WHERE id = p_branch_id;
    IF v_pharmacy_id IS NULL THEN
        RAISE EXCEPTION 'Branch not found';
    END IF;
    
    -- Check for existing active record (already clocked in)
    SELECT COUNT(*) INTO v_active_record
    FROM attendance_records
    WHERE employee_id = p_employee_id AND status = 'active';
    
    IF v_active_record > 0 THEN
        RAISE EXCEPTION 'Employee is already clocked in';
    END IF;
    
    -- Create attendance record
    INSERT INTO attendance_records (
        employee_id, branch_id, pharmacy_id,
        clock_in, clock_in_ip, device_info, status
    ) VALUES (
        p_employee_id, p_branch_id, v_pharmacy_id,
        NOW(), p_ip_address, p_device_info, 'active'
    ) RETURNING id INTO v_attendance_id;
    
    RETURN v_attendance_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Clock out an employee
-- ============================================
CREATE OR REPLACE FUNCTION clock_out_employee(
    p_employee_id UUID,
    p_notes TEXT DEFAULT NULL,
    p_ip_address INET DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_attendance_id UUID;
BEGIN
    -- Find active record
    SELECT id INTO v_attendance_id
    FROM attendance_records
    WHERE employee_id = p_employee_id AND status = 'active'
    ORDER BY clock_in DESC
    LIMIT 1
    FOR UPDATE; -- Lock to prevent race conditions
    
    IF v_attendance_id IS NULL THEN
        RAISE EXCEPTION 'No active clock-in record found';
    END IF;
    
    -- Update with clock-out time
    UPDATE attendance_records SET
        clock_out = NOW(),
        clock_out_ip = p_ip_address,
        notes = COALESCE(notes, notes), -- Append if provided
        status = 'completed',
        updated_at = NOW()
    WHERE id = v_attendance_id;
    
    RETURN v_attendance_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- FUNCTION: Get today's attendance for a branch
-- ============================================
CREATE OR REPLACE FUNCTION get_today_attendance(p_branch_id UUID)
RETURNS TABLE (
    id UUID,
    employee_id UUID,
    employee_name VARCHAR,
    clock_in TIMESTAMPTZ,
    clock_out TIMESTAMPTZ,
    total_minutes INTEGER,
    status VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ar.id,
        ar.employee_id,
        CONCAT(e.first_name, ' ', e.last_name) as employee_name,
        ar.clock_in,
        ar.clock_out,
        ar.total_minutes,
        ar.status
    FROM attendance_records ar
    JOIN employees e ON ar.employee_id = e.id
    WHERE ar.branch_id = p_branch_id
      AND DATE(ar.clock_in) = CURRENT_DATE
      AND ar.pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    ORDER BY ar.clock_in;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- Updated triggers
-- ============================================
CREATE TRIGGER update_audit_logs_updated_at BEFORE UPDATE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    
CREATE TRIGGER update_attendance_records_updated_at BEFORE UPDATE ON attendance_records
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- VIEW: recent_audit_summary
-- Description: Quick view for dashboards showing recent activity
-- ============================================
CREATE OR REPLACE VIEW recent_audit_summary AS
SELECT 
    al.id,
    al.pharmacy_id,
    al.action,
    al.entity_type,
    al.actor_display_name as actor_name,
    al.actor_email,
    al.created_at,
    al.success,
    al.severity,
    CASE 
        WHEN al.entity_id IS NOT NULL THEN
            CONCAT(al.entity_type, ': ', LEFT(al.entity_id::text, 8), '...')
        ELSE NULL
    END as entity_preview,
    al.changes_summary
FROM audit_logs al
WHERE al.created_at > NOW() - INTERVAL '7 days'
ORDER BY al.created_at DESC
LIMIT 1000;

COMMENT ON VIEW recent_audit_summary IS 'Dashboard view - shows last 7 days of audit activity';

-- ============================================
-- Final Comments
-- ============================================
COMMENT ON SCHEMA public IS 'Pharmacy OS Phase 1 Schema - Foundation complete';
