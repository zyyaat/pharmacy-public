--
-- PostgreSQL database dump
--

\restrict AOpwBPkyfYgAq40aRMtaNXN1NYXMg0VZgtSe0Hfa82Wamb0ddMa0ZGYWpZXM35y

-- Dumped from database version 16.10
-- Dumped by pg_dump version 16.10

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'Pharmacy OS Database - Phase 2: Holding Company Layer Added';


--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: account_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.account_status AS ENUM (
    'active',
    'suspended',
    'cancelled',
    'trial'
);


--
-- Name: company_plan; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.company_plan AS ENUM (
    'free',
    'starter',
    'professional',
    'enterprise',
    'custom'
);


--
-- Name: company_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.company_status AS ENUM (
    'active',
    'suspended',
    'trial',
    'cancelled'
);


--
-- Name: company_user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.company_user_role AS ENUM (
    'super_admin',
    'company_admin',
    'company_manager',
    'company_viewer'
);


--
-- Name: currency_code; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.currency_code AS ENUM (
    'USD',
    'EUR',
    'GBP',
    'EGP',
    'SAR',
    'AED',
    'QAR',
    'KWD',
    'BHD',
    'OMR',
    'JOD',
    'LBP',
    'SYP',
    'IQD',
    'LYD',
    'DZD',
    'TND',
    'MAD',
    'YER'
);


--
-- Name: dosage_form; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.dosage_form AS ENUM (
    'tablet',
    'capsule',
    'syrup',
    'drop',
    'injection',
    'ointment',
    'cream',
    'gel',
    'powder',
    'solution',
    'suspension',
    'inhaler',
    'patch',
    'suppository',
    'eye_drops',
    'ear_drops',
    'nasal_spray',
    'other'
);


--
-- Name: employee_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.employee_status AS ENUM (
    'active',
    'inactive',
    'on_leave',
    'terminated'
);


--
-- Name: movement_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.movement_type AS ENUM (
    'purchase',
    'sale',
    'return_to_supplier',
    'return_from_customer',
    'adjustment',
    'transfer_in',
    'transfer_out',
    'expiry_writeoff',
    'damage_writeoff',
    'theft_loss',
    'production_input',
    'production_output'
);


--
-- Name: prescription_required; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.prescription_required AS ENUM (
    'yes',
    'no',
    'otc_only'
);


--
-- Name: product_category; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.product_category AS ENUM (
    'medication',
    'supplement',
    'medical_device',
    'personal_care',
    'cosmetic',
    'food_supplement',
    'herbal',
    'vaccine',
    'consumable',
    'other'
);


--
-- Name: unit_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.unit_type AS ENUM (
    'box',
    'strip',
    'blister',
    'tablet',
    'capsule',
    'bottle',
    'vial',
    'ampoule',
    'tube',
    'jar',
    'packet',
    'piece',
    'set',
    'kit',
    'liter',
    'milliliter',
    'gram',
    'kilogram',
    'meter',
    'other'
);


--
-- Name: calculate_batch_current_stock(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_batch_current_stock(p_batch_id uuid) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_current_stock NUMERIC(12,4);
BEGIN
    SELECT COALESCE(SUM(quantity), 0) INTO v_current_stock
    FROM stock_movements
    WHERE batch_id = p_batch_id;
    
    RETURN v_current_stock;
END;
$$;


--
-- Name: calculate_product_total_stock(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_product_total_stock(p_pharmacy_product_id uuid, p_branch_id uuid DEFAULT NULL::uuid) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_total_stock NUMERIC(12,4);
BEGIN
    IF p_branch_id IS NULL THEN
        -- Sum across all branches
        SELECT COALESCE(SUM(sm.quantity), 0) INTO v_total_stock
        FROM stock_movements sm
        JOIN inventory_batches ib ON sm.batch_id = ib.id
        WHERE ib.pharmacy_product_id = p_pharmacy_product_id;
    ELSE
        -- Sum for specific branch only
        SELECT COALESCE(SM(sm.quantity), 0) INTO v_total_stock
        FROM stock_movements sm
        JOIN inventory_batches ib ON sm.batch_id = ib.id
        WHERE ib.pharmacy_product_id = p_pharmacy_product_id
          AND ib.branch_id = p_branch_id;
    END IF;
    
    RETURN v_total_stock;
END;
$$;


--
-- Name: clock_in_employee(uuid, uuid, inet, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clock_in_employee(p_employee_id uuid, p_branch_id uuid, p_ip_address inet DEFAULT NULL::inet, p_device_info jsonb DEFAULT NULL::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: clock_out_employee(uuid, text, inet); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clock_out_employee(p_employee_id uuid, p_notes text DEFAULT NULL::text, p_ip_address inet DEFAULT NULL::inet) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: convert_units(uuid, public.unit_type, public.unit_type, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.convert_units(p_product_id uuid, p_from_unit public.unit_type, p_to_unit public.unit_type, p_quantity numeric) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    v_factor NUMERIC(12,6);
    v_result NUMERIC(12,4);
BEGIN
    -- Same unit, no conversion needed
    IF p_from_unit = p_to_unit THEN
        RETURN p_quantity;
    END IF;
    
    -- Try direct conversion
    SELECT conversion_factor INTO v_factor FROM unit_conversions
    WHERE global_product_id = p_product_id 
      AND from_unit = p_from_unit 
      AND to_unit = p_to_unit
    LIMIT 1;
    
    IF v_factor IS NOT NULL THEN
        RETURN p_quantity * v_factor;
    END IF;
    
    -- Try reverse conversion (e.g., we have tablet→strip but need strip→tablet)
    SELECT conversion_factor INTO v_factor FROM unit_conversions
    WHERE global_product_id = p_product_id 
      AND from_unit = p_to_unit 
      AND to_unit = p_from_unit
    LIMIT 1;
    
    IF v_factor IS NOT NULL THEN
        RETURN p_quantity / v_factor;
    END IF;
    
    -- No conversion found - raise exception
    RAISE EXCEPTION 'No conversion found from % to % for product %', p_from_unit, p_to_unit, p_product_id;
END;
$$;


--
-- Name: FUNCTION convert_units(p_product_id uuid, p_from_unit public.unit_type, p_to_unit public.unit_type, p_quantity numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.convert_units(p_product_id uuid, p_from_unit public.unit_type, p_to_unit public.unit_type, p_quantity numeric) IS 'Convert quantity from one unit to another based on product conversion rules';


--
-- Name: get_company_user_permissions(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_company_user_permissions(p_company_user_id uuid) RETURNS character varying[]
    LANGUAGE plpgsql STABLE
    AS $$
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
$$;


--
-- Name: get_employee_permissions(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employee_permissions(p_employee_id uuid) RETURNS character varying[]
    LANGUAGE plpgsql STABLE
    AS $$
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
$$;


--
-- Name: get_or_create_default_branch(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_or_create_default_branch(p_pharmacy_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: get_today_attendance(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_today_attendance(p_branch_id uuid) RETURNS TABLE(id uuid, employee_id uuid, employee_name character varying, clock_in timestamp with time zone, clock_out timestamp with time zone, total_minutes integer, status character varying)
    LANGUAGE plpgsql STABLE
    AS $$
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
$$;


--
-- Name: grant_permission_to_company_user(uuid, character varying, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.grant_permission_to_company_user(p_company_user_id uuid, p_permission_key character varying, p_granted_by uuid, p_notes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: grant_permission_to_employee(uuid, character varying, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.grant_permission_to_employee(p_employee_id uuid, p_permission_key character varying, p_granted_by uuid, p_notes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: has_company_permission(uuid, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_company_permission(p_company_user_id uuid, p_permission_key character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
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
$$;


--
-- Name: has_permission(uuid, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_permission(p_employee_id uuid, p_permission_key character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
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
$$;


--
-- Name: increment_company_user_permission_version(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_company_user_permission_version(p_company_user_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: increment_employee_permission_version(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_employee_permission_version(p_employee_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: log_audit(uuid, uuid, uuid, character varying, character varying, uuid, jsonb, jsonb, inet, text, boolean, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_audit(p_pharmacy_id uuid, p_account_id uuid, p_actor_id uuid, p_action character varying, p_entity_type character varying, p_entity_id uuid DEFAULT NULL::uuid, p_old_values jsonb DEFAULT NULL::jsonb, p_new_values jsonb DEFAULT NULL::jsonb, p_ip_address inet DEFAULT NULL::inet, p_user_agent text DEFAULT NULL::text, p_success boolean DEFAULT true, p_severity character varying DEFAULT 'info'::character varying) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: revoke_permission_from_company_user(uuid, character varying, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revoke_permission_from_company_user(p_company_user_id uuid, p_permission_key character varying, p_revoked_by uuid, p_reason text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: revoke_permission_from_employee(uuid, character varying, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revoke_permission_from_employee(p_employee_id uuid, p_permission_key character varying, p_revoked_by uuid, p_reason text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: trigger_company_permission_version_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_company_permission_version_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: trigger_increment_permission_version(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_increment_permission_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: update_batch_quantity_on_movement(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_batch_quantity_on_movement() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update the batch's cached quantity (optimization for frequent reads)
    UPDATE inventory_batches 
    SET quantity = calculate_batch_current_quality(NEW.batch_id),
        updated_at = NOW()
    WHERE id = NEW.batch_id;
    
    RETURN NEW;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    company_name character varying(255) NOT NULL,
    contact_email character varying(255) NOT NULL,
    contact_phone character varying(50),
    billing_address text,
    status public.account_status DEFAULT 'trial'::public.account_status,
    trial_ends_at timestamp with time zone,
    subscription_plan character varying(50) DEFAULT 'free'::character varying,
    subscription_current_period_start timestamp with time zone,
    subscription_current_period_end timestamp with time zone,
    default_currency public.currency_code DEFAULT 'USD'::public.currency_code,
    timezone character varying(100) DEFAULT 'UTC'::character varying,
    locale character varying(10) DEFAULT 'en-US'::character varying,
    settings jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    company_id uuid,
    deleted_at timestamp with time zone
);


--
-- Name: TABLE accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.accounts IS 'Top-level tenant accounts - represents the paying customer';


--
-- Name: COLUMN accounts.company_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.accounts.company_id IS 'Link to holding company. NULL for legacy/migrated accounts.';


--
-- Name: attendance_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_records (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    pharmacy_id uuid NOT NULL,
    clock_in timestamp with time zone DEFAULT now() NOT NULL,
    clock_out timestamp with time zone,
    total_minutes integer GENERATED ALWAYS AS (
CASE
    WHEN (clock_out IS NOT NULL) THEN (EXTRACT(epoch FROM (clock_out - clock_in)) / (60)::numeric)
    ELSE NULL::numeric
END) STORED,
    status character varying(20) DEFAULT 'active'::character varying,
    notes text,
    adjustment_reason text,
    adjusted_by uuid,
    adjusted_at timestamp with time zone,
    clock_in_ip inet,
    clock_in_location point,
    clock_out_ip inet,
    clock_out_location point,
    device_info jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT attendance_records_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'completed'::character varying, 'adjusted'::character varying, 'missed_clockout'::character varying])::text[])))
);


--
-- Name: TABLE attendance_records; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.attendance_records IS 'Employee attendance records - non-partitioned (add partitioning when >5M records)';


--
-- Name: COLUMN attendance_records.total_minutes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance_records.total_minutes IS 'Auto-calculated duration in minutes between clock_in and clock_out';


--
-- Name: COLUMN attendance_records.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance_records.status IS 'active=clocked in, completed=clocked out, adjusted=manually changed, missed_clockout=forgot to clock out';


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    pharmacy_id uuid NOT NULL,
    account_id uuid NOT NULL,
    actor_id uuid,
    actor_email character varying(255),
    actor_display_name character varying(255),
    actor_role character varying(100),
    actor_auth_user_id uuid,
    action character varying(100) NOT NULL,
    action_category character varying(50),
    entity_type character varying(100) NOT NULL,
    entity_id uuid,
    old_values jsonb,
    new_values jsonb,
    changes_summary text,
    fields_changed text[],
    request_id character varying(100),
    ip_address inet,
    user_agent text,
    client_info jsonb,
    success boolean DEFAULT true,
    error_message text,
    duration_ms integer,
    severity character varying(20) DEFAULT 'info'::character varying,
    tags text[],
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE audit_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.audit_logs IS 'Comprehensive audit trail - immutable log of all system actions';


--
-- Name: COLUMN audit_logs.old_values; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.old_values IS 'JSON snapshot before change (for updates/deletes)';


--
-- Name: COLUMN audit_logs.new_values; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.new_values IS 'JSON snapshot after change (for creates/updates)';


--
-- Name: COLUMN audit_logs.severity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.severity IS 'Severity level: info, warning, critical';


--
-- Name: auth_email_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_email_tokens (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    principal_type character varying(32) NOT NULL,
    principal_id uuid NOT NULL,
    purpose character varying(32) NOT NULL,
    token_hash bytea NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT auth_email_tokens_principal_type_check CHECK (((principal_type)::text = ANY ((ARRAY['company_user'::character varying, 'employee'::character varying])::text[]))),
    CONSTRAINT auth_email_tokens_purpose_check CHECK (((purpose)::text = ANY ((ARRAY['verify_email'::character varying, 'reset_password'::character varying])::text[])))
);


--
-- Name: auth_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_sessions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    family_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    principal_type character varying(32) NOT NULL,
    principal_id uuid NOT NULL,
    access_token_hash bytea NOT NULL,
    refresh_token_hash bytea NOT NULL,
    access_expires_at timestamp with time zone NOT NULL,
    refresh_expires_at timestamp with time zone NOT NULL,
    last_used_at timestamp with time zone DEFAULT now() NOT NULL,
    user_agent text,
    ip_address inet,
    replaced_by_session_id uuid,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT auth_sessions_principal_type_check CHECK (((principal_type)::text = ANY ((ARRAY['company_user'::character varying, 'employee'::character varying])::text[])))
);


--
-- Name: branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branches (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    pharmacy_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    code character varying(50),
    phone character varying(50),
    email character varying(255),
    address_line1 character varying(255),
    address_line2 character varying(255),
    city character varying(100),
    state_province character varying(100),
    postal_code character varying(20),
    country character varying(100),
    manager_employee_id uuid,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE branches; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.branches IS 'Optional sub-branches within a pharmacy for multi-location setups';


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    name_ar character varying(255),
    legal_name character varying(255),
    registration_number character varying(100),
    email character varying(255) NOT NULL,
    phone character varying(50),
    website character varying(255),
    address_line1 character varying(255),
    address_line2 character varying(255),
    city character varying(100),
    state_province character varying(100),
    postal_code character varying(20),
    country character varying(100) DEFAULT 'EG'::character varying,
    status public.company_status DEFAULT 'trial'::public.company_status,
    plan public.company_plan DEFAULT 'free'::public.company_plan,
    trial_ends_at timestamp with time zone,
    subscription_current_period_start timestamp with time zone,
    subscription_current_period_end timestamp with time zone,
    max_accounts integer DEFAULT 1,
    max_users_per_account integer DEFAULT 10,
    default_currency character varying(10) DEFAULT 'EGP'::character varying,
    timezone character varying(100) DEFAULT 'Africa/Cairo'::character varying,
    locale character varying(10) DEFAULT 'ar-EG'::character varying,
    settings jsonb DEFAULT '{}'::jsonb,
    logo_url text,
    primary_color character varying(7),
    secondary_color character varying(7),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    is_active boolean GENERATED ALWAYS AS ((deleted_at IS NULL)) STORED
);


--
-- Name: TABLE companies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.companies IS '⭐ HOLDING COMPANY ⭐ - Top-level SaaS customer. Can own multiple pharmacy accounts.';


--
-- Name: COLUMN companies.max_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.companies.max_accounts IS 'Maximum number of pharmacy accounts this company can create';


--
-- Name: COLUMN companies.settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.companies.settings IS 'JSONB for flexible configuration (features, integrations, etc.)';


--
-- Name: company_user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_user_permissions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    company_user_id uuid NOT NULL,
    permission_id integer NOT NULL,
    granted_by uuid NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_by uuid,
    revoked_at timestamp with time zone,
    revocation_reason text,
    is_active boolean GENERATED ALWAYS AS ((revoked_at IS NULL)) STORED,
    notes text
);


--
-- Name: TABLE company_user_permissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.company_user_permissions IS '⭐ SOURCE OF TRUTH ⭐ - Company user permissions. Same pattern as employee_permissions.';


--
-- Name: company_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_users (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    company_id uuid NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    last_login_at timestamp with time zone,
    login_attempts integer DEFAULT 0,
    locked_until timestamp with time zone,
    password_changed_at timestamp with time zone DEFAULT now(),
    must_change_password boolean DEFAULT false,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    display_name character varying(200),
    avatar_url text,
    phone character varying(50),
    role public.company_user_role DEFAULT 'company_viewer'::public.company_user_role,
    permission_version integer DEFAULT 0,
    is_active boolean DEFAULT true,
    email_verified_at timestamp with time zone,
    email_verification_token character varying(255),
    password_reset_token character varying(255),
    password_reset_expires_at timestamp with time zone,
    preferences jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);


--
-- Name: TABLE company_users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.company_users IS 'Company-level users with custom auth (bcrypt). These are NOT pharmacy employees.';


--
-- Name: COLUMN company_users.password_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.company_users.password_hash IS 'bcrypt hash - custom auth, NOT Supabase Auth';


--
-- Name: COLUMN company_users.permission_version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.company_users.permission_version IS 'Incremented on permission change - for JWT cache invalidation';


--
-- Name: global_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.global_products (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    generic_name character varying(255),
    brand_name character varying(255),
    dosage_form public.dosage_form NOT NULL,
    strength character varying(100),
    product_category public.product_category DEFAULT 'medication'::public.product_category,
    requires_prescription public.prescription_required DEFAULT 'no'::public.prescription_required,
    controlled_substance boolean DEFAULT false,
    schedule_category character varying(50),
    barcode character varying(100),
    barcode_type character varying(20) DEFAULT 'EAN13'::character varying,
    national_code character varying(100),
    manufacturer_sku character varying(100),
    manufacturer_name character varying(255),
    manufacturer_country character varying(100),
    active_ingredient character varying(255),
    therapeutic_class character varying(100),
    atc_code character varying(20),
    default_unit public.unit_type DEFAULT 'tablet'::public.unit_type,
    description text,
    storage_instructions text,
    is_active boolean DEFAULT true,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE global_products; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.global_products IS 'Global Product Master - shared catalog defined once, used by all pharmacies';


--
-- Name: COLUMN global_products.barcode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.global_products.barcode IS 'Primary barcode (EAN-13, UPC, etc.) - must be unique when present';


--
-- Name: inventory_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_batches (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    pharmacy_product_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    batch_number character varying(100) NOT NULL,
    barcode character varying(100),
    quantity numeric(12,4) DEFAULT 0 NOT NULL,
    unit public.unit_type DEFAULT 'tablet'::public.unit_type NOT NULL,
    cost_per_unit numeric(12,4) DEFAULT 0 NOT NULL,
    total_cost numeric(14,2) GENERATED ALWAYS AS ((quantity * cost_per_unit)) STORED,
    manufacture_date date,
    expiry_date date,
    days_until_expiry integer,
    supplier_name character varying(255),
    supplier_reference character varying(100),
    location character varying(100),
    is_reserved boolean DEFAULT false,
    is_quarantined boolean DEFAULT false,
    quarantine_reason text,
    received_date date DEFAULT CURRENT_DATE NOT NULL,
    received_by uuid,
    reference_type character varying(50),
    reference_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT inventory_batches_quantity_check CHECK ((quantity >= (0)::numeric))
);


--
-- Name: TABLE inventory_batches; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.inventory_batches IS 'Physical inventory batches - tracks actual stock with expiry and cost per batch';


--
-- Name: COLUMN inventory_batches.quantity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_batches.quantity IS 'Current quantity - should equal SUM of related stock_movements';


--
-- Name: COLUMN inventory_batches.days_until_expiry; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_batches.days_until_expiry IS 'Calculated field - triggers alerts when low';


--
-- Name: pharmacy_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pharmacy_products (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    pharmacy_id uuid NOT NULL,
    global_product_id uuid NOT NULL,
    cost_price numeric(12,4) DEFAULT 0,
    selling_price numeric(12,4) NOT NULL,
    margin_percentage numeric(5,2),
    tax_rate numeric(5,2) DEFAULT 0,
    tax_category character varying(50),
    min_stock_level numeric(12,4) DEFAULT 0,
    max_stock_level numeric(12,4),
    reorder_quantity numeric(12,4),
    preferred_supplier_id uuid,
    internal_sku character varying(100),
    shelf_location character varying(100),
    bin_location character varying(50),
    is_active boolean DEFAULT true,
    is_discontinued boolean DEFAULT false,
    first_added_at timestamp with time zone DEFAULT now(),
    last_received_at timestamp with time zone,
    last_sold_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE pharmacy_products; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.pharmacy_products IS 'Pharmacy-specific product data - pricing, stock levels, settings per tenant';


--
-- Name: current_inventory; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.current_inventory AS
 SELECT ib.id AS batch_id,
    pp.id AS pharmacy_product_id,
    pp.pharmacy_id,
    ib.branch_id,
    gp.id AS global_product_id,
    gp.name AS product_name,
    gp.generic_name,
    gp.brand_name,
    gp.barcode,
    gp.dosage_form,
    gp.strength,
    ib.batch_number,
    ib.unit,
    public.calculate_batch_current_stock(ib.id) AS quantity,
    ib.cost_per_unit,
    ib.total_cost,
    ib.expiry_date,
    ib.days_until_expiry,
    pp.selling_price,
    pp.min_stock_level,
    b.name AS branch_name,
        CASE
            WHEN (public.calculate_batch_current_stock(ib.id) <= pp.min_stock_level) THEN 'low_stock'::text
            WHEN ((ib.expiry_date IS NOT NULL) AND (ib.expiry_date <= (CURRENT_DATE + '90 days'::interval))) THEN 'expiring_soon'::text
            WHEN ib.is_quarantined THEN 'quarantined'::text
            ELSE 'normal'::text
        END AS status
   FROM (((public.inventory_batches ib
     JOIN public.pharmacy_products pp ON ((ib.pharmacy_product_id = pp.id)))
     JOIN public.global_products gp ON ((pp.global_product_id = gp.id)))
     LEFT JOIN public.branches b ON ((ib.branch_id = b.id)))
  WHERE ((ib.quantity > (0)::numeric) OR (public.calculate_batch_current_stock(ib.id) > (0)::numeric));


--
-- Name: VIEW current_inventory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.current_inventory IS 'Pre-calculated view of current inventory - use for dashboards and reports';


--
-- Name: COLUMN current_inventory.quantity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.current_inventory.quantity IS 'Calculated from SUM(stock_movements) - always accurate';


--
-- Name: employee_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_permissions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    permission_id integer NOT NULL,
    granted_by uuid NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_by uuid,
    revoked_at timestamp with time zone,
    revocation_reason text,
    is_active boolean GENERATED ALWAYS AS ((revoked_at IS NULL)) STORED,
    notes text
);


--
-- Name: TABLE employee_permissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employee_permissions IS '⭐ SOURCE OF TRUTH ⭐ - Actual permissions for each employee. This table determines authorization.';


--
-- Name: COLUMN employee_permissions.revoked_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employee_permissions.revoked_at IS 'Soft delete - keeps full audit history';


--
-- Name: COLUMN employee_permissions.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employee_permissions.is_active IS 'Computed: true if not revoked. Use this for fast lookups.';


--
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    account_id uuid NOT NULL,
    pharmacy_id uuid NOT NULL,
    branch_id uuid,
    auth_user_id uuid,
    email character varying(255) NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    display_name character varying(200),
    phone character varying(50),
    address text,
    emergency_contact_name character varying(100),
    emergency_contact_phone character varying(50),
    employee_id_internal character varying(50),
    job_title character varying(100),
    department character varying(100),
    hire_date date,
    termination_date date,
    base_salary numeric(12,2),
    status public.employee_status DEFAULT 'active'::public.employee_status,
    permission_version integer DEFAULT 0,
    avatar_url text,
    preferences jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    password_hash character varying(255),
    is_active boolean DEFAULT true NOT NULL,
    email_verified_at timestamp with time zone,
    last_login_at timestamp with time zone,
    login_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    password_changed_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE employees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employees IS 'Staff members - authentication handled by the Go API';


--
-- Name: COLUMN employees.auth_user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.auth_user_id IS 'Legacy authentication provider identifier; unused by the Go API';


--
-- Name: COLUMN employees.permission_version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.permission_version IS 'Incremented when permissions change - used for JWT cache invalidation';


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    id integer NOT NULL,
    key character varying(100) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    module character varying(50) NOT NULL,
    category character varying(50),
    parent_key character varying(100),
    is_system boolean DEFAULT false,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT permissions_valid_key_format CHECK (((key)::text ~ '^[a-z][a-z_]*(\.[a-z_]+)+$'::text))
);


--
-- Name: TABLE permissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.permissions IS 'Master catalog of all available permissions in the system';


--
-- Name: COLUMN permissions.key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permissions.key IS 'Permission identifier in format: module.action (e.g., employees.create)';


--
-- Name: COLUMN permissions.is_system; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permissions.is_system IS 'System permissions cannot be deleted via API';


--
-- Name: permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.permissions_id_seq OWNED BY public.permissions.id;


--
-- Name: pharmacies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pharmacies (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    account_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    legal_name character varying(255),
    license_number character varying(100),
    tax_id character varying(100),
    email character varying(255),
    phone character varying(50),
    website character varying(255),
    address_line1 character varying(255),
    address_line2 character varying(255),
    city character varying(100),
    state_province character varying(100),
    postal_code character varying(20),
    country character varying(100) DEFAULT 'US'::character varying,
    is_main_branch boolean DEFAULT true,
    default_branch_id uuid,
    currency public.currency_code,
    auto_expiry_alert_days integer DEFAULT 90,
    low_stock_threshold integer DEFAULT 10,
    enable_batch_tracking boolean DEFAULT true,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE pharmacies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.pharmacies IS 'Individual pharmacy locations belonging to an account';


--
-- Name: COLUMN pharmacies.is_main_branch; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pharmacies.is_main_branch IS 'True for single-pharmacy or headquarters in multi-branch setup';


--
-- Name: recent_audit_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.recent_audit_summary AS
 SELECT id,
    pharmacy_id,
    action,
    entity_type,
    actor_display_name AS actor_name,
    actor_email,
    created_at,
    success,
    severity,
        CASE
            WHEN (entity_id IS NOT NULL) THEN concat(entity_type, ': ', "left"((entity_id)::text, 8), '...')
            ELSE NULL::text
        END AS entity_preview,
    changes_summary
   FROM public.audit_logs al
  WHERE (created_at > (now() - '7 days'::interval))
  ORDER BY created_at DESC
 LIMIT 1000;


--
-- Name: VIEW recent_audit_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.recent_audit_summary IS 'Dashboard view - shows last 7 days of audit activity';


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    role_id uuid NOT NULL,
    permission_id integer NOT NULL,
    granted_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE role_permissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.role_permissions IS 'Default permission assignments for roles - used as template when assigning role to employee';


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(100) NOT NULL,
    display_name character varying(255),
    description text,
    is_system boolean DEFAULT false,
    is_default boolean DEFAULT false,
    account_id uuid,
    is_active boolean DEFAULT true,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE roles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.roles IS 'Role templates - default permission sets for convenience. NOT the source of truth for authorization.';


--
-- Name: COLUMN roles.account_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.roles.account_id IS 'NULL = system role (available to all accounts), otherwise account-specific';


--
-- Name: stock_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_movements (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    batch_id uuid NOT NULL,
    movement_type public.movement_type NOT NULL,
    quantity numeric(12,4) NOT NULL,
    unit public.unit_type NOT NULL,
    reference_type character varying(50),
    reference_id uuid,
    quantity_before numeric(12,4),
    quantity_after numeric(12,4),
    unit_cost numeric(12,4),
    total_cost numeric(14,2),
    created_by uuid NOT NULL,
    approved_by uuid,
    reason text,
    notes text,
    ip_address inet,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stock_movements_quantity_check CHECK ((quantity <> (0)::numeric))
);


--
-- Name: TABLE stock_movements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.stock_movements IS 'SOURCE OF TRUTH for all inventory quantities - every stock change must be recorded here';


--
-- Name: COLUMN stock_movements.quantity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stock_movements.quantity IS 'Positive = stock IN, Negative = stock OUT';


--
-- Name: COLUMN stock_movements.reference_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.stock_movements.reference_type IS 'Source document type: purchase_order, sale, adjustment, transfer, etc.';


--
-- Name: unit_conversions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unit_conversions (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    global_product_id uuid NOT NULL,
    from_unit public.unit_type NOT NULL,
    to_unit public.unit_type NOT NULL,
    conversion_factor numeric(12,6) NOT NULL,
    is_standard boolean DEFAULT true,
    description character varying(255),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT unit_conversions_conversion_factor_check CHECK ((conversion_factor > (0)::numeric))
);


--
-- Name: TABLE unit_conversions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.unit_conversions IS 'Unit conversion rules - enables box→strip→tablet calculations';


--
-- Name: v_company_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_company_summary AS
SELECT
    NULL::uuid AS id,
    NULL::character varying(255) AS name,
    NULL::character varying(255) AS name_ar,
    NULL::character varying(255) AS legal_name,
    NULL::character varying(100) AS registration_number,
    NULL::character varying(255) AS email,
    NULL::character varying(50) AS phone,
    NULL::character varying(255) AS website,
    NULL::character varying(255) AS address_line1,
    NULL::character varying(255) AS address_line2,
    NULL::character varying(100) AS city,
    NULL::character varying(100) AS state_province,
    NULL::character varying(20) AS postal_code,
    NULL::character varying(100) AS country,
    NULL::public.company_status AS status,
    NULL::public.company_plan AS plan,
    NULL::timestamp with time zone AS trial_ends_at,
    NULL::timestamp with time zone AS subscription_current_period_start,
    NULL::timestamp with time zone AS subscription_current_period_end,
    NULL::integer AS max_accounts,
    NULL::integer AS max_users_per_account,
    NULL::character varying(10) AS default_currency,
    NULL::character varying(100) AS timezone,
    NULL::character varying(10) AS locale,
    NULL::jsonb AS settings,
    NULL::text AS logo_url,
    NULL::character varying(7) AS primary_color,
    NULL::character varying(7) AS secondary_color,
    NULL::timestamp with time zone AS created_at,
    NULL::timestamp with time zone AS updated_at,
    NULL::timestamp with time zone AS deleted_at,
    NULL::boolean AS is_active,
    NULL::bigint AS total_accounts,
    NULL::bigint AS active_accounts,
    NULL::bigint AS total_users;


--
-- Name: VIEW v_company_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_company_summary IS 'Company overview with account/user counts';


--
-- Name: v_company_user_with_permissions; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_company_user_with_permissions AS
 SELECT cu.id,
    cu.company_id,
    cu.email,
    cu.password_hash,
    cu.last_login_at,
    cu.login_attempts,
    cu.locked_until,
    cu.password_changed_at,
    cu.must_change_password,
    cu.first_name,
    cu.last_name,
    cu.display_name,
    cu.avatar_url,
    cu.phone,
    cu.role,
    cu.permission_version,
    cu.is_active,
    cu.email_verified_at,
    cu.email_verification_token,
    cu.password_reset_token,
    cu.password_reset_expires_at,
    cu.preferences,
    cu.created_at,
    cu.updated_at,
    cu.deleted_at,
    COALESCE(perm_count.permission_count, (0)::bigint) AS total_permissions,
    ARRAY( SELECT p.key
           FROM (public.company_user_permissions cup2
             JOIN public.permissions p ON ((cup2.permission_id = p.id)))
          WHERE ((cup2.company_user_id = cu.id) AND (cup2.is_active = true))) AS permission_keys
   FROM (public.company_users cu
     LEFT JOIN ( SELECT company_user_permissions.company_user_id,
            count(*) AS permission_count
           FROM public.company_user_permissions
          WHERE (company_user_permissions.is_active = true)
          GROUP BY company_user_permissions.company_user_id) perm_count ON ((perm_count.company_user_id = cu.id)))
  WHERE (cu.deleted_at IS NULL);


--
-- Name: VIEW v_company_user_with_permissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_company_user_with_permissions IS 'Company users with their permission details';


--
-- Name: permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions ALTER COLUMN id SET DEFAULT nextval('public.permissions_id_seq'::regclass);


--
-- Data for Name: accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.accounts (id, company_name, contact_email, contact_phone, billing_address, status, trial_ends_at, subscription_plan, subscription_current_period_start, subscription_current_period_end, default_currency, timezone, locale, settings, created_at, updated_at, company_id, deleted_at) FROM stdin;
\.


--
-- Data for Name: attendance_records; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.attendance_records (id, employee_id, branch_id, pharmacy_id, clock_in, clock_out, status, notes, adjustment_reason, adjusted_by, adjusted_at, clock_in_ip, clock_in_location, clock_out_ip, clock_out_location, device_info, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.audit_logs (id, pharmacy_id, account_id, actor_id, actor_email, actor_display_name, actor_role, actor_auth_user_id, action, action_category, entity_type, entity_id, old_values, new_values, changes_summary, fields_changed, request_id, ip_address, user_agent, client_info, success, error_message, duration_ms, severity, tags, notes, created_at) FROM stdin;
\.


--
-- Data for Name: auth_email_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_email_tokens (id, principal_type, principal_id, purpose, token_hash, expires_at, used_at, created_at) FROM stdin;
\.


--
-- Data for Name: auth_sessions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_sessions (id, family_id, principal_type, principal_id, access_token_hash, refresh_token_hash, access_expires_at, refresh_expires_at, last_used_at, user_agent, ip_address, replaced_by_session_id, revoked_at, created_at) FROM stdin;
eed513df-298e-4f8a-a58f-ce87379fb79f	4041017d-453b-4608-b550-3fab22c7a25e	company_user	72757c97-41a6-4819-b7aa-3c1d9def727f	\\xdfe439504bf4e66c61325b4011bf64cfa693c5489ce650a7dff01de387feb360	\\x3df00f3cbb923a2f3a38a9dcea0c39f781b3a1808fce5610f4937aff3fb58c68	2026-09-05 16:21:29.557748+00	2026-10-05 16:06:29.557748+00	2026-09-05 16:06:29.573684+00	curl/8.14.1	127.0.0.1	\N	\N	2026-09-05 16:06:29.558409+00
c3df5818-40b1-46d4-8f10-70bbec411d4c	8782655c-7e3c-48de-8ddd-c2798cc74f1e	company_user	72757c97-41a6-4819-b7aa-3c1d9def727f	\\xc00f2cefacaca18235a2e33e7f9dec7ebbb5a69a13567541238abb04ac527caa	\\x320f3f19babc63ae8df7f1a1bb45a37776c25ef70120136e6628c920a58d958a	2026-09-05 16:23:40.740708+00	2026-10-05 16:08:40.740708+00	2026-09-05 16:08:40.751632+00	curl/8.14.1	127.0.0.1	\N	\N	2026-09-05 16:08:40.740847+00
6bf0bd8e-c635-489c-bf74-72b92fdd4d2f	2ffea73e-3f67-4967-b3f6-fd2107e7d513	company_user	72757c97-41a6-4819-b7aa-3c1d9def727f	\\x7e0322fdc5fd40cb0bdf626986c4be0b7acc7dc60883dd56ef1bee24cc5cb918	\\x3b0e6773f3abe28fb4a01c38fc31d214f9cabfb37914114fbeacb52998ed36b5	2026-09-05 16:24:59.637135+00	2026-10-05 16:09:59.637135+00	2026-09-05 16:09:59.637649+00	curl/8.14.1	127.0.0.1	\N	\N	2026-09-05 16:09:59.637649+00
e275208f-d6e4-4a72-a080-b8f1b3ae7337	edd4e067-5090-4ef5-acb4-69e906316c55	company_user	72757c97-41a6-4819-b7aa-3c1d9def727f	\\xc706ac2c18f07f2c37c08860b78c32b5e60e7584487290667c829207a71e51d4	\\x2c8a31326b47317730cfc22a5832406fa979f9ba6061c5902c4dca6cda66d55f	2026-09-05 16:27:13.108103+00	2026-10-05 16:12:13.108103+00	2026-09-05 16:12:13.10822+00	curl/8.14.1	127.0.0.1	\N	\N	2026-09-05 16:12:13.10822+00
25d75cc2-f679-4c7f-a89c-5156c296d77b	237cc7da-faf1-455e-be8a-3af335819777	company_user	72757c97-41a6-4819-b7aa-3c1d9def727f	\\xf01f5aa13b40b0392605d7ec85b1c50cdcfd87da92b2b2ccb584e10e90a887ef	\\xcb2e50b41b75130eb758d7409ec9754784284673fd87e2536138e24dac09978b	2026-09-05 16:27:29.077306+00	2026-10-05 16:12:29.077306+00	2026-09-05 16:14:54.526132+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Mobile Safari/537.36	196.156.17.173	\N	2026-09-05 16:14:54.538219+00	2026-09-05 16:12:29.077424+00
de60c564-b6f3-42a8-a2da-eaf7b0b21fa2	da1dd28c-db61-46fd-b2f9-9d16378d6114	company_user	72757c97-41a6-4819-b7aa-3c1d9def727f	\\xf79515b2e6f8da99dbefd5896cba632c5b77090a60df6048ae37f5df5bc42a42	\\x8c4f2cf3e4ecf78965d30cb8e6f3fec07cb6d5d9b66cf84076270bcdf33c8bf7	2026-09-05 16:30:17.905049+00	2026-10-05 16:15:17.905049+00	2026-09-05 16:15:39.852142+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Mobile Safari/537.36	196.156.17.173	\N	\N	2026-09-05 16:15:17.9054+00
\.


--
-- Data for Name: branches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.branches (id, pharmacy_id, name, code, phone, email, address_line1, address_line2, city, state_province, postal_code, country, manager_employee_id, is_active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: companies; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.companies (id, name, name_ar, legal_name, registration_number, email, phone, website, address_line1, address_line2, city, state_province, postal_code, country, status, plan, trial_ends_at, subscription_current_period_start, subscription_current_period_end, max_accounts, max_users_per_account, default_currency, timezone, locale, settings, logo_url, primary_color, secondary_color, created_at, updated_at, deleted_at) FROM stdin;
efd1c5f4-20a7-42c5-a876-f7451a38e845	Pharmacy OS Administration	إدارة Pharmacy OS	\N	\N	zyyat@outlook.sa	\N	\N	\N	\N	\N	\N	\N	EG	active	enterprise	\N	\N	\N	1	10	EGP	Africa/Cairo	ar-EG	{}	\N	\N	\N	2026-09-05 16:06:03.26231+00	2026-09-05 16:06:03.26231+00	\N
\.


--
-- Data for Name: company_user_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.company_user_permissions (id, company_user_id, permission_id, granted_by, granted_at, revoked_by, revoked_at, revocation_reason, notes) FROM stdin;
db2f3774-d6d8-4dc1-a4fe-b305bbd883be	72757c97-41a6-4819-b7aa-3c1d9def727f	1	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
918b5cc1-36e3-4de1-91a1-84930a28e511	72757c97-41a6-4819-b7aa-3c1d9def727f	2	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
0b4bf105-97bf-48d7-9508-aeb85e32c8d3	72757c97-41a6-4819-b7aa-3c1d9def727f	3	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
d11748a8-f674-4fe0-b0d2-16402e22a47e	72757c97-41a6-4819-b7aa-3c1d9def727f	4	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
4c789d55-3bf3-4cc2-be5b-2466978db1ea	72757c97-41a6-4819-b7aa-3c1d9def727f	5	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
0556b79c-ac35-4b09-83d8-c1e4c6db2005	72757c97-41a6-4819-b7aa-3c1d9def727f	6	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
5d49a481-f91f-4a43-8ab2-fa93af638f40	72757c97-41a6-4819-b7aa-3c1d9def727f	7	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
6a3422c0-d3d4-4c1f-a709-158822a2f215	72757c97-41a6-4819-b7aa-3c1d9def727f	8	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
eadbd6a3-5a4e-400b-9f61-78b430cb968c	72757c97-41a6-4819-b7aa-3c1d9def727f	9	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
e967101d-dcc6-426d-9cae-f2bbb2cb88a5	72757c97-41a6-4819-b7aa-3c1d9def727f	10	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
06a9339b-b9d1-430e-a1d7-901f29bc305c	72757c97-41a6-4819-b7aa-3c1d9def727f	11	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
b9cd77ce-cacf-4f9d-b714-0af45bd4dd94	72757c97-41a6-4819-b7aa-3c1d9def727f	12	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
f395cb6c-c883-47ee-b9df-77e9a2cdf88a	72757c97-41a6-4819-b7aa-3c1d9def727f	13	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
fc8288f6-0f69-499b-a038-524f2b2ba43f	72757c97-41a6-4819-b7aa-3c1d9def727f	14	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
0a5630e3-0546-4456-b637-65eda05d6612	72757c97-41a6-4819-b7aa-3c1d9def727f	15	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
435e5813-2d42-4ef7-bb2e-1ab97a4d1609	72757c97-41a6-4819-b7aa-3c1d9def727f	16	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
d79d6c19-593d-4bff-adb3-eccd440a967d	72757c97-41a6-4819-b7aa-3c1d9def727f	17	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
9d6c3af5-1926-48f2-b9a6-22a1415bf8e4	72757c97-41a6-4819-b7aa-3c1d9def727f	18	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
b4579b07-71c7-43ea-b6d3-d32aaa74001a	72757c97-41a6-4819-b7aa-3c1d9def727f	19	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
ed1c0632-4aea-416c-9bab-5a919a0990b0	72757c97-41a6-4819-b7aa-3c1d9def727f	20	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
ad2cd434-52f9-4c74-9e52-4d857ae747d7	72757c97-41a6-4819-b7aa-3c1d9def727f	21	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
ac0b2e7d-9d81-429e-87c5-a42232c0daf1	72757c97-41a6-4819-b7aa-3c1d9def727f	22	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
9294470a-45c1-4787-a97f-4e88860af8fa	72757c97-41a6-4819-b7aa-3c1d9def727f	23	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
f414a197-d1c1-45ab-aea1-528f62489d56	72757c97-41a6-4819-b7aa-3c1d9def727f	24	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
9ede7f07-f696-4ee9-ba08-4b27c045218b	72757c97-41a6-4819-b7aa-3c1d9def727f	25	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
38580cb6-048d-437e-b7d7-6383d5898cef	72757c97-41a6-4819-b7aa-3c1d9def727f	26	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
9693f909-e81a-45bf-91d6-19a0e3e3558e	72757c97-41a6-4819-b7aa-3c1d9def727f	27	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
f091b9f4-e8b3-4227-99af-760e49a7b2d7	72757c97-41a6-4819-b7aa-3c1d9def727f	28	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
da37d207-ce0e-4261-949d-ef1c439bd3b8	72757c97-41a6-4819-b7aa-3c1d9def727f	29	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
bb677e68-0dbd-4945-8c28-15c61d8dde62	72757c97-41a6-4819-b7aa-3c1d9def727f	30	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
ed9a2801-a9ff-43cd-9a6b-f4a043ddd3e7	72757c97-41a6-4819-b7aa-3c1d9def727f	31	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
319aaf3b-6f25-4e80-bbb4-ca5a494605b6	72757c97-41a6-4819-b7aa-3c1d9def727f	32	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
152dce79-8ace-4da3-8e2b-faf5b0019af4	72757c97-41a6-4819-b7aa-3c1d9def727f	33	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
6b0a543c-5b9c-4fb6-bf7c-fe2e2a147b07	72757c97-41a6-4819-b7aa-3c1d9def727f	34	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
86914c0b-d0fa-4927-a859-f3a7fa272a54	72757c97-41a6-4819-b7aa-3c1d9def727f	35	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
d73cf56c-00ed-4ae5-a945-efb988c69b5b	72757c97-41a6-4819-b7aa-3c1d9def727f	36	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
7e2fe4ff-cdbc-4fa9-a909-5e4dc9e0f3c4	72757c97-41a6-4819-b7aa-3c1d9def727f	37	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
f585ad7a-bb49-45d1-ae30-919f17156e46	72757c97-41a6-4819-b7aa-3c1d9def727f	38	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
998dfff0-9e5e-4705-b471-61406279b495	72757c97-41a6-4819-b7aa-3c1d9def727f	39	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
e8e828e4-8786-460c-b78a-7e81b7bea493	72757c97-41a6-4819-b7aa-3c1d9def727f	40	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
e5456d8e-8ad2-43e0-a0ba-e12c5e3e97a7	72757c97-41a6-4819-b7aa-3c1d9def727f	41	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
32b4e7d7-48a0-4ea5-8f70-b81957b1e618	72757c97-41a6-4819-b7aa-3c1d9def727f	42	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
c30fcc24-236d-4edc-83fa-8198a901316a	72757c97-41a6-4819-b7aa-3c1d9def727f	43	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
5dbef67a-e57f-4f72-b37d-4fcee02a1631	72757c97-41a6-4819-b7aa-3c1d9def727f	44	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
0cdb8c95-ef0b-498c-b7ff-8b354a8e33dd	72757c97-41a6-4819-b7aa-3c1d9def727f	45	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
0817d555-3178-4855-9ae0-8c7e441a5c53	72757c97-41a6-4819-b7aa-3c1d9def727f	46	72757c97-41a6-4819-b7aa-3c1d9def727f	2026-09-05 16:06:18.735335+00	\N	\N	\N	Initial system administrator permissions
\.


--
-- Data for Name: company_users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.company_users (id, company_id, email, password_hash, last_login_at, login_attempts, locked_until, password_changed_at, must_change_password, first_name, last_name, display_name, avatar_url, phone, role, permission_version, is_active, email_verified_at, email_verification_token, password_reset_token, password_reset_expires_at, preferences, created_at, updated_at, deleted_at) FROM stdin;
72757c97-41a6-4819-b7aa-3c1d9def727f	efd1c5f4-20a7-42c5-a876-f7451a38e845	zyyat@outlook.sa	$2a$10$jboZN2ZTP4W5lvj0pi5aN.fVddQ1tBjVqa1axYqx/SHg9YYNOLAPG	2026-09-05 16:15:17.898604+00	0	\N	2026-09-05 16:12:12.760954+00	f	مسؤول	النظام	مسؤول النظام	\N	\N	super_admin	46	t	2026-09-05 16:06:03.413444+00	\N	\N	\N	{}	2026-09-05 16:06:03.413444+00	2026-09-05 16:15:17.898604+00	\N
\.


--
-- Data for Name: employee_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.employee_permissions (id, employee_id, permission_id, granted_by, granted_at, revoked_by, revoked_at, revocation_reason, notes) FROM stdin;
\.


--
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.employees (id, account_id, pharmacy_id, branch_id, auth_user_id, email, first_name, last_name, display_name, phone, address, emergency_contact_name, emergency_contact_phone, employee_id_internal, job_title, department, hire_date, termination_date, base_salary, status, permission_version, avatar_url, preferences, created_at, updated_at, password_hash, is_active, email_verified_at, last_login_at, login_attempts, locked_until, password_changed_at) FROM stdin;
\.


--
-- Data for Name: global_products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.global_products (id, name, generic_name, brand_name, dosage_form, strength, product_category, requires_prescription, controlled_substance, schedule_category, barcode, barcode_type, national_code, manufacturer_sku, manufacturer_name, manufacturer_country, active_ingredient, therapeutic_class, atc_code, default_unit, description, storage_instructions, is_active, created_by, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: inventory_batches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventory_batches (id, pharmacy_product_id, branch_id, batch_number, barcode, quantity, unit, cost_per_unit, manufacture_date, expiry_date, days_until_expiry, supplier_name, supplier_reference, location, is_reserved, is_quarantined, quarantine_reason, received_date, received_by, reference_type, reference_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.permissions (id, key, name, description, module, category, parent_key, is_system, sort_order, created_at) FROM stdin;
1	employees.view	View Employees	Can view employee list and details	employees	read	\N	t	1	2026-09-05 16:04:51.516878+00
2	employees.create	Create Employees	Can add new employees to the pharmacy	employees	write	\N	t	2	2026-09-05 16:04:51.516878+00
3	employees.update	Update Employees	Can edit employee information	employees	write	\N	t	3	2026-09-05 16:04:51.516878+00
4	employees.delete	Delete Employees	Can remove employees from the system	employees	delete	\N	t	4	2026-09-05 16:04:51.516878+00
5	employees.manage_permissions	Manage Employee Permissions	Can grant/revoke permissions to other employees	employees	admin	\N	t	5	2026-09-05 16:04:51.516878+00
6	inventory.view	View Inventory	Can view inventory levels and details	inventory	read	\N	t	10	2026-09-05 16:04:51.516878+00
7	inventory.adjust	Adjust Inventory	Can make stock adjustments (increase/decrease)	inventory	write	\N	t	11	2026-09-05 16:04:51.516878+00
8	inventory.receive	Receive Goods	Can receive goods into inventory (create batches)	inventory	write	\N	t	12	2026-09-05 16:04:51.516878+00
9	inventory.transfer	Transfer Stock	Can transfer stock between branches	inventory	write	\N	t	13	2026-09-05 16:04:51.516878+00
10	inventory.writeoff	Write Off Stock	Can write off expired or damaged stock	inventory	delete	\N	t	14	2026-09-05 16:04:51.516878+00
11	inventory.manage_products	Manage Products	Can add/edit products from global catalog	inventory	admin	\N	t	15	2026-09-05 16:04:51.516878+00
12	products.global.manage	Manage Global Products	Can add/edit products in the global catalog (System Admin only)	products	admin	\N	t	20	2026-09-05 16:04:51.516878+00
13	products.pharmacy.add	Add Pharmacy Products	Can add products from global catalog to pharmacy	products	write	\N	t	21	2026-09-05 16:04:51.516878+00
14	products.pharmacy.pricing	Set Product Pricing	Can set selling prices and costs for pharmacy products	products	write	\N	t	22	2026-09-05 16:04:51.516878+00
15	branches.view	View Branches	Can view branch information	branches	read	\N	t	30	2026-09-05 16:04:51.516878+00
16	branches.create	Create Branches	Can create new branches	branches	write	\N	t	31	2026-09-05 16:04:51.516878+00
17	branches.update	Update Branches	Can edit branch information	branches	write	\N	t	32	2026-09-05 16:04:51.516878+00
18	branches.delete	Delete Branches	Can delete branches	branches	delete	\N	t	33	2026-09-05 16:04:51.516878+00
19	reports.inventory	Inventory Reports	Can view inventory reports and analytics	reports	read	\N	t	40	2026-09-05 16:04:51.516878+00
20	reports.sales	Sales Reports	Can view sales reports and analytics	reports	read	\N	t	41	2026-09-05 16:04:51.516878+00
21	reports.employees	Employee Reports	Can view employee reports and attendance	reports	read	\N	t	42	2026-09-05 16:04:51.516878+00
22	reports.financial	Financial Reports	Can view financial reports (P&L, etc.)	reports	read	\N	t	43	2026-09-05 16:04:51.516878+00
23	settings.general	General Settings	Can manage general pharmacy settings	settings	admin	\N	t	50	2026-09-05 16:04:51.516878+00
24	settings.billing	Billing Settings	Can manage billing and subscription settings	settings	admin	\N	t	51	2026-09-05 16:04:51.516878+00
25	settings.integrations	Integration Settings	Can manage third-party integrations	settings	admin	\N	t	52	2026-09-05 16:04:51.516878+00
26	attendance.view	View Attendance	Can view attendance records	attendance	read	\N	t	60	2026-09-05 16:04:51.516878+00
27	attendance.clock_in_out	Clock In/Out	Can clock in and out	attendance	write	\N	t	61	2026-09-05 16:04:51.516878+00
28	attendance.manage	Manage Attendance	Can edit attendance records (admin function)	attendance	admin	\N	t	62	2026-09-05 16:04:51.516878+00
29	pharmacy.admin	Pharmacy Administrator	Full administrative access to pharmacy (implies most permissions)	pharmacy	admin	\N	t	99	2026-09-05 16:04:51.516878+00
30	companies.view	View Companies	Can view company information and details	companies	read	\N	t	70	2026-09-05 16:04:58.391123+00
31	companies.create	Create Companies	Can create new companies (Super Admin only)	companies	admin	\N	t	71	2026-09-05 16:04:58.391123+00
32	companies.update	Update Companies	Can update company information	companies	write	\N	t	72	2026-09-05 16:04:58.391123+00
33	companies.delete	Delete Companies	Can delete/suspend companies (Super Admin only)	companies	delete	\N	t	73	2026-09-05 16:04:58.391123+00
34	companies.manage_subscription	Manage Subscriptions	Can manage company subscriptions and billing	companies	admin	\N	t	74	2026-09-05 16:04:58.391123+00
35	company_users.view	View Company Users	Can view company user list	company_users	read	\N	t	80	2026-09-05 16:04:58.391123+00
36	company_users.create	Create Company Users	Can add new company users	company_users	write	\N	t	81	2026-09-05 16:04:58.391123+00
37	company_users.update	Update Company Users	Can edit company user information	company_users	write	\N	t	82	2026-09-05 16:04:58.391123+00
38	company_users.delete	Delete Company Users	Can remove company users	company_users	delete	\N	t	83	2026-09-05 16:04:58.391123+00
39	company_users.manage_permissions	Manage User Permissions	Can grant/revoke permissions to company users	company_users	admin	\N	t	84	2026-09-05 16:04:58.391123+00
40	accounts.view	View Accounts	Can view pharmacy accounts under company	accounts	read	\N	t	90	2026-09-05 16:04:58.391123+00
41	accounts.create	Create Accounts	Can create new pharmacy accounts	accounts	write	\N	t	91	2026-09-05 16:04:58.391123+00
42	accounts.update	Update Accounts	Can edit account information	accounts	write	\N	t	92	2026-09-05 16:04:58.391123+00
43	accounts.delete	Delete Accounts	Can delete/suspend accounts	accounts	delete	\N	t	93	2026-09-05 16:04:58.391123+00
44	platform.admin	Platform Administrator	Full platform administration access	platform	admin	\N	t	99	2026-09-05 16:04:58.391123+00
45	platform.analytics	View Platform Analytics	Can view platform-wide analytics	platform	read	\N	t	98	2026-09-05 16:04:58.391123+00
46	platform.audit	View Audit Logs	Can view system-wide audit logs	platform	read	\N	t	97	2026-09-05 16:04:58.391123+00
\.


--
-- Data for Name: pharmacies; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pharmacies (id, account_id, name, legal_name, license_number, tax_id, email, phone, website, address_line1, address_line2, city, state_province, postal_code, country, is_main_branch, default_branch_id, currency, auto_expiry_alert_days, low_stock_threshold, enable_batch_tracking, is_active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: pharmacy_products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pharmacy_products (id, pharmacy_id, global_product_id, cost_price, selling_price, margin_percentage, tax_rate, tax_category, min_stock_level, max_stock_level, reorder_quantity, preferred_supplier_id, internal_sku, shelf_location, bin_location, is_active, is_discontinued, first_added_at, last_received_at, last_sold_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: role_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.role_permissions (id, role_id, permission_id, granted_at) FROM stdin;
494e3f5a-7640-47a5-8749-a6923c2d3809	00000000-0000-0000-0000-000000000001	1	2026-09-05 16:04:51.516878+00
7c259ad7-bb4f-4cf2-9018-dbee905edee3	00000000-0000-0000-0000-000000000001	2	2026-09-05 16:04:51.516878+00
ab02893b-f490-4209-8afd-1fce207bf5fb	00000000-0000-0000-0000-000000000001	3	2026-09-05 16:04:51.516878+00
03b025e8-d90e-4fb2-8400-d3a8baff3e50	00000000-0000-0000-0000-000000000001	4	2026-09-05 16:04:51.516878+00
1ee3a1c1-c2ff-423a-8192-369506f0a836	00000000-0000-0000-0000-000000000001	5	2026-09-05 16:04:51.516878+00
b00edab1-9c01-47f5-addb-ae96e131f92a	00000000-0000-0000-0000-000000000001	6	2026-09-05 16:04:51.516878+00
75aaef20-79d4-4c2d-945e-a44b9690458b	00000000-0000-0000-0000-000000000001	7	2026-09-05 16:04:51.516878+00
14fff75e-f174-4df8-8959-f3150d53de4a	00000000-0000-0000-0000-000000000001	8	2026-09-05 16:04:51.516878+00
6b211a12-744d-49d7-bd65-1340a5203562	00000000-0000-0000-0000-000000000001	9	2026-09-05 16:04:51.516878+00
fca4cb00-8f37-41e4-b1f4-c3abfbe8ffdc	00000000-0000-0000-0000-000000000001	10	2026-09-05 16:04:51.516878+00
db205ab7-c46b-4b85-9a41-5282d4cd51fe	00000000-0000-0000-0000-000000000001	11	2026-09-05 16:04:51.516878+00
738474b4-9f99-44e8-a109-72e8ff8e4990	00000000-0000-0000-0000-000000000001	13	2026-09-05 16:04:51.516878+00
d0b03015-903c-4b83-8e8d-3235411d4e4b	00000000-0000-0000-0000-000000000001	14	2026-09-05 16:04:51.516878+00
266d6ae7-812f-442f-b8e6-8df146d4a13e	00000000-0000-0000-0000-000000000001	15	2026-09-05 16:04:51.516878+00
4053354e-cd07-4fa9-afdf-6f014042a7f6	00000000-0000-0000-0000-000000000001	16	2026-09-05 16:04:51.516878+00
efca7587-f479-4ee3-9e27-54598c2283f4	00000000-0000-0000-0000-000000000001	17	2026-09-05 16:04:51.516878+00
e6af247b-428b-45ca-a4bc-ab34d4b9b9e1	00000000-0000-0000-0000-000000000001	18	2026-09-05 16:04:51.516878+00
ffaf34bf-8033-4e4f-9ea8-cd769a31ed77	00000000-0000-0000-0000-000000000001	19	2026-09-05 16:04:51.516878+00
8cc8d8f1-7b09-496b-91f2-06578f0a1dd1	00000000-0000-0000-0000-000000000001	20	2026-09-05 16:04:51.516878+00
50becb30-3497-40a3-bb9f-a9212f18291d	00000000-0000-0000-0000-000000000001	21	2026-09-05 16:04:51.516878+00
c0fe133e-5bb3-45da-8c64-c3a459915045	00000000-0000-0000-0000-000000000001	22	2026-09-05 16:04:51.516878+00
c5c48a30-e94c-4973-9224-6a291252f176	00000000-0000-0000-0000-000000000001	23	2026-09-05 16:04:51.516878+00
360db0c1-ebbb-4ce4-a306-e18d454a8d2d	00000000-0000-0000-0000-000000000001	24	2026-09-05 16:04:51.516878+00
b02f50c1-8aa3-4845-b5c7-cf0ab0452764	00000000-0000-0000-0000-000000000001	25	2026-09-05 16:04:51.516878+00
75862d56-11a9-41d2-8493-a9837e61fff2	00000000-0000-0000-0000-000000000001	26	2026-09-05 16:04:51.516878+00
471e074c-3a02-4230-98e4-703122b5dbd7	00000000-0000-0000-0000-000000000001	27	2026-09-05 16:04:51.516878+00
3efe96f2-dc21-4de9-be02-6cf2a78bd3ad	00000000-0000-0000-0000-000000000001	28	2026-09-05 16:04:51.516878+00
24c80b8e-097e-4401-a585-ddc8e1239a21	00000000-0000-0000-0000-000000000001	29	2026-09-05 16:04:51.516878+00
28383258-d47f-4713-876f-3263be755abf	00000000-0000-0000-0000-000000000002	1	2026-09-05 16:04:51.516878+00
295dc8da-cd75-4f1f-ab81-740aaa7f4870	00000000-0000-0000-0000-000000000002	6	2026-09-05 16:04:51.516878+00
257466c8-4487-413e-8a2a-cdffc560c120	00000000-0000-0000-0000-000000000002	7	2026-09-05 16:04:51.516878+00
11d34a9d-2be6-4f15-985a-27058228df86	00000000-0000-0000-0000-000000000002	8	2026-09-05 16:04:51.516878+00
acfa9d8f-d85e-4b2d-b9e6-f97f6611335e	00000000-0000-0000-0000-000000000002	9	2026-09-05 16:04:51.516878+00
da0f0b08-5f0a-4296-b4af-03c1bb513ab2	00000000-0000-0000-0000-000000000002	13	2026-09-05 16:04:51.516878+00
185944fa-4d55-4c6e-a998-0a3bafb1b962	00000000-0000-0000-0000-000000000002	14	2026-09-05 16:04:51.516878+00
3d2e35b9-7fac-457f-ae2f-5de8b2202660	00000000-0000-0000-0000-000000000002	15	2026-09-05 16:04:51.516878+00
98e23dd2-dd90-48eb-8e5f-2998d4a0eba1	00000000-0000-0000-0000-000000000002	19	2026-09-05 16:04:51.516878+00
614d0586-49c6-45d9-b2dc-efe87b12ca9c	00000000-0000-0000-0000-000000000002	20	2026-09-05 16:04:51.516878+00
16c2e5ab-7cad-4c81-8402-9393cbcaa77e	00000000-0000-0000-0000-000000000002	23	2026-09-05 16:04:51.516878+00
172b93f7-ffff-4b97-8c3b-da6b600ba5cb	00000000-0000-0000-0000-000000000002	26	2026-09-05 16:04:51.516878+00
85ac98e8-710a-46fc-a217-acbbfee9d41f	00000000-0000-0000-0000-000000000002	27	2026-09-05 16:04:51.516878+00
b784adb8-8b84-42b5-bd30-ba2941dc2cc0	00000000-0000-0000-0000-000000000003	1	2026-09-05 16:04:51.516878+00
fd13ea23-3508-4d70-977c-82c6f0724596	00000000-0000-0000-0000-000000000003	6	2026-09-05 16:04:51.516878+00
66c1414c-af39-430f-966f-a4b878dde97c	00000000-0000-0000-0000-000000000003	15	2026-09-05 16:04:51.516878+00
ad930ac7-21cf-48af-a078-4fd4c7c01e43	00000000-0000-0000-0000-000000000003	20	2026-09-05 16:04:51.516878+00
b076186d-65e7-443e-8742-6e50a9650a4a	00000000-0000-0000-0000-000000000003	27	2026-09-05 16:04:51.516878+00
5d8358e0-a03b-44ec-8ae7-76251b72664c	00000000-0000-0000-0000-000000000004	1	2026-09-05 16:04:51.516878+00
54e1123a-9b51-4b02-a560-41d21521d313	00000000-0000-0000-0000-000000000004	6	2026-09-05 16:04:51.516878+00
de1b8fdf-a7ed-452d-8461-6a16391e8c1a	00000000-0000-0000-0000-000000000004	7	2026-09-05 16:04:51.516878+00
452c1320-ac82-49b7-8eb0-0c7babd12284	00000000-0000-0000-0000-000000000004	8	2026-09-05 16:04:51.516878+00
575bce1c-418d-48b6-ba67-1a54a38feed6	00000000-0000-0000-0000-000000000004	9	2026-09-05 16:04:51.516878+00
c74a9402-85fc-4362-bd0c-ffbf9114144e	00000000-0000-0000-0000-000000000004	10	2026-09-05 16:04:51.516878+00
65074dc9-12b8-49a2-ac74-d7db132d93ed	00000000-0000-0000-0000-000000000004	13	2026-09-05 16:04:51.516878+00
9933d73a-2fe6-43f6-8810-02e3cdd9302c	00000000-0000-0000-0000-000000000004	14	2026-09-05 16:04:51.516878+00
fb53495e-a2c3-4088-948f-6ba37a0e1fa6	00000000-0000-0000-0000-000000000004	15	2026-09-05 16:04:51.516878+00
dfb0c855-9377-4a26-a948-ad6d6402e0b7	00000000-0000-0000-0000-000000000004	19	2026-09-05 16:04:51.516878+00
76c6a54e-db3c-4f48-8992-45776b96d16a	00000000-0000-0000-0000-000000000004	26	2026-09-05 16:04:51.516878+00
895c1d68-3684-434a-9b3f-fe3337df888e	00000000-0000-0000-0000-000000000004	27	2026-09-05 16:04:51.516878+00
ea5710b7-1842-4080-9a6e-aed4ecbda8b5	00000000-0000-0000-0000-000000000005	1	2026-09-05 16:04:51.516878+00
23685e62-0c0e-46f2-a284-0ae543a6dabf	00000000-0000-0000-0000-000000000005	2	2026-09-05 16:04:51.516878+00
ec7832c3-0fc0-4da8-949f-87d656e428fd	00000000-0000-0000-0000-000000000005	3	2026-09-05 16:04:51.516878+00
bdc0d9ce-5222-4c0a-b061-4044e510cf0b	00000000-0000-0000-0000-000000000005	5	2026-09-05 16:04:51.516878+00
50d42af5-e40f-4be8-88b1-dae8d2ef092a	00000000-0000-0000-0000-000000000005	21	2026-09-05 16:04:51.516878+00
10756f86-038e-4da5-b9b0-217999dbd17c	00000000-0000-0000-0000-000000000005	26	2026-09-05 16:04:51.516878+00
2d9bdcd2-047e-43bb-8df5-f4dd62745656	00000000-0000-0000-0000-000000000005	28	2026-09-05 16:04:51.516878+00
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.roles (id, name, display_name, description, is_system, is_default, account_id, is_active, sort_order, created_at, updated_at) FROM stdin;
00000000-0000-0000-0000-000000000001	pharmacy_admin	Pharmacy Admin / مدير الصيدلية	Full access to all pharmacy features including user management	t	f	\N	t	1	2026-09-05 16:04:51.516878+00	2026-09-05 16:04:51.516878+00
00000000-0000-0000-0000-000000000002	pharmacist	Pharmacist / صيدلي	Can manage inventory, process sales, view reports	t	t	\N	t	2	2026-09-05 16:04:51.516878+00	2026-09-05 16:04:51.516878+00
00000000-0000-0000-0000-000000000003	cashier	Cashier / كاشير	Can process sales and view basic inventory	t	t	\N	t	3	2026-09-05 16:04:51.516878+00	2026-09-05 16:04:51.516878+00
00000000-0000-0000-0000-000000000004	inventory_manager	Inventory Manager / مسؤول المخزون	Full inventory management including adjustments and transfers	t	f	\N	t	4	2026-09-05 16:04:51.516878+00	2026-09-05 16:04:51.516878+00
00000000-0000-0000-0000-000000000005	hr_manager	HR Manager / مسؤول الموارد البشرية	Can manage employees and their permissions	t	f	\N	t	5	2026-09-05 16:04:51.516878+00	2026-09-05 16:04:51.516878+00
\.


--
-- Data for Name: stock_movements; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.stock_movements (id, batch_id, movement_type, quantity, unit, reference_type, reference_id, quantity_before, quantity_after, unit_cost, total_cost, created_by, approved_by, reason, notes, ip_address, user_agent, created_at) FROM stdin;
\.


--
-- Data for Name: unit_conversions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.unit_conversions (id, global_product_id, from_unit, to_unit, conversion_factor, is_standard, description, created_at) FROM stdin;
\.


--
-- Name: permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.permissions_id_seq', 46, true);


--
-- Name: accounts accounts_contact_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_contact_email_key UNIQUE (contact_email);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: attendance_records attendance_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: auth_email_tokens auth_email_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_email_tokens
    ADD CONSTRAINT auth_email_tokens_pkey PRIMARY KEY (id);


--
-- Name: auth_email_tokens auth_email_tokens_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_email_tokens
    ADD CONSTRAINT auth_email_tokens_token_hash_key UNIQUE (token_hash);


--
-- Name: auth_sessions auth_sessions_access_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_access_token_hash_key UNIQUE (access_token_hash);


--
-- Name: auth_sessions auth_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_pkey PRIMARY KEY (id);


--
-- Name: auth_sessions auth_sessions_refresh_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_refresh_token_hash_key UNIQUE (refresh_token_hash);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: companies companies_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_email_key UNIQUE (email);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: company_user_permissions company_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_user_permissions
    ADD CONSTRAINT company_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: company_users company_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_users
    ADD CONSTRAINT company_users_pkey PRIMARY KEY (id);


--
-- Name: company_users company_users_unique_email_per_company; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_users
    ADD CONSTRAINT company_users_unique_email_per_company UNIQUE (email, company_id);


--
-- Name: employee_permissions employee_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_permissions
    ADD CONSTRAINT employee_permissions_pkey PRIMARY KEY (id);


--
-- Name: employees employees_auth_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_auth_user_id_key UNIQUE (auth_user_id);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- Name: employees employees_unique_email_per_pharmacy; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_unique_email_per_pharmacy UNIQUE (email, pharmacy_id);


--
-- Name: global_products global_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.global_products
    ADD CONSTRAINT global_products_pkey PRIMARY KEY (id);


--
-- Name: inventory_batches inventory_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_pkey PRIMARY KEY (id);


--
-- Name: inventory_batches inventory_batches_unique_batch; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_unique_batch UNIQUE (pharmacy_product_id, branch_id, batch_number);


--
-- Name: attendance_records no_overlapping_attendance; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT no_overlapping_attendance EXCLUDE USING gist (employee_id WITH =, tstzrange(clock_in, COALESCE(clock_out, 'infinity'::timestamp with time zone)) WITH &&);


--
-- Name: permissions permissions_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_key_key UNIQUE (key);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: pharmacies pharmacies_license_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pharmacies
    ADD CONSTRAINT pharmacies_license_number_key UNIQUE (license_number);


--
-- Name: pharmacies pharmacies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pharmacies
    ADD CONSTRAINT pharmacies_pkey PRIMARY KEY (id);


--
-- Name: pharmacy_products pharmacy_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pharmacy_products
    ADD CONSTRAINT pharmacy_products_pkey PRIMARY KEY (id);


--
-- Name: pharmacy_products pharmacy_products_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pharmacy_products
    ADD CONSTRAINT pharmacy_products_unique UNIQUE (pharmacy_id, global_product_id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_unique UNIQUE (role_id, permission_id);


--
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: stock_movements stock_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_pkey PRIMARY KEY (id);


--
-- Name: unit_conversions unique_conversion_per_product; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unit_conversions
    ADD CONSTRAINT unique_conversion_per_product UNIQUE (global_product_id, from_unit, to_unit);


--
-- Name: unit_conversions unit_conversions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unit_conversions
    ADD CONSTRAINT unit_conversions_pkey PRIMARY KEY (id);


--
-- Name: company_user_perms_unique_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX company_user_perms_unique_active ON public.company_user_permissions USING btree (company_user_id, permission_id) WHERE (revoked_at IS NULL);


--
-- Name: idx_accounts_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_accounts_company_id ON public.accounts USING btree (company_id) WHERE (company_id IS NOT NULL);


--
-- Name: idx_accounts_contact_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_accounts_contact_email ON public.accounts USING btree (contact_email);


--
-- Name: idx_accounts_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_accounts_status ON public.accounts USING btree (status);


--
-- Name: idx_attendance_branch_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_branch_date ON public.attendance_records USING btree (branch_id, clock_in DESC);


--
-- Name: idx_attendance_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_branch_id ON public.attendance_records USING btree (branch_id);


--
-- Name: idx_attendance_clock_in; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_clock_in ON public.attendance_records USING btree (clock_in DESC);


--
-- Name: idx_attendance_clock_out; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_clock_out ON public.attendance_records USING btree (clock_out) WHERE (clock_out IS NOT NULL);


--
-- Name: idx_attendance_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_employee_date ON public.attendance_records USING btree (employee_id, clock_in DESC);


--
-- Name: idx_attendance_employee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_employee_id ON public.attendance_records USING btree (employee_id);


--
-- Name: idx_attendance_pharmacy_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_pharmacy_date ON public.attendance_records USING btree (pharmacy_id, clock_in DESC);


--
-- Name: idx_attendance_pharmacy_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_pharmacy_id ON public.attendance_records USING btree (pharmacy_id);


--
-- Name: idx_attendance_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_status ON public.attendance_records USING btree (status);


--
-- Name: idx_attendance_status_clock_in; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_status_clock_in ON public.attendance_records USING btree (status, clock_in);


--
-- Name: idx_audit_logs_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_account_id ON public.audit_logs USING btree (account_id);


--
-- Name: idx_audit_logs_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_action ON public.audit_logs USING btree (action);


--
-- Name: idx_audit_logs_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_actor ON public.audit_logs USING btree (actor_id) WHERE (actor_id IS NOT NULL);


--
-- Name: idx_audit_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at DESC);


--
-- Name: idx_audit_logs_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (entity_type, entity_id) WHERE (entity_id IS NOT NULL);


--
-- Name: idx_audit_logs_pharmacy_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_pharmacy_action ON public.audit_logs USING btree (pharmacy_id, action, created_at DESC);


--
-- Name: idx_audit_logs_pharmacy_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_pharmacy_date ON public.audit_logs USING btree (pharmacy_id, created_at DESC);


--
-- Name: idx_audit_logs_pharmacy_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_pharmacy_id ON public.audit_logs USING btree (pharmacy_id);


--
-- Name: idx_auth_email_tokens_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_email_tokens_lookup ON public.auth_email_tokens USING btree (token_hash, purpose) WHERE (used_at IS NULL);


--
-- Name: idx_auth_email_tokens_principal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_email_tokens_principal ON public.auth_email_tokens USING btree (principal_type, principal_id, purpose) WHERE (used_at IS NULL);


--
-- Name: idx_auth_sessions_family; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_sessions_family ON public.auth_sessions USING btree (family_id) WHERE (revoked_at IS NULL);


--
-- Name: idx_auth_sessions_principal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_sessions_principal ON public.auth_sessions USING btree (principal_type, principal_id) WHERE (revoked_at IS NULL);


--
-- Name: idx_branches_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_branches_active ON public.branches USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_branches_code_pharmacy; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_branches_code_pharmacy ON public.branches USING btree (code, pharmacy_id) WHERE (code IS NOT NULL);


--
-- Name: idx_branches_pharmacy_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_branches_pharmacy_id ON public.branches USING btree (pharmacy_id);


--
-- Name: idx_companies_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_active ON public.companies USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_companies_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_email ON public.companies USING btree (email);


--
-- Name: idx_companies_plan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_plan ON public.companies USING btree (plan);


--
-- Name: idx_companies_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_status ON public.companies USING btree (status);


--
-- Name: idx_companies_trial_end; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_trial_end ON public.companies USING btree (trial_ends_at) WHERE (trial_ends_at IS NOT NULL);


--
-- Name: idx_company_user_perms_granted_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_user_perms_granted_by ON public.company_user_permissions USING btree (granted_by);


--
-- Name: idx_company_user_perms_permission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_user_perms_permission ON public.company_user_permissions USING btree (permission_id) WHERE (is_active = true);


--
-- Name: idx_company_user_perms_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_user_perms_user ON public.company_user_permissions USING btree (company_user_id) WHERE (is_active = true);


--
-- Name: idx_company_users_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_users_active ON public.company_users USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_company_users_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_users_company_id ON public.company_users USING btree (company_id);


--
-- Name: idx_company_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_users_email ON public.company_users USING btree (email);


--
-- Name: idx_company_users_email_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_users_email_lower ON public.company_users USING btree (lower((email)::text)) WHERE (deleted_at IS NULL);


--
-- Name: idx_company_users_email_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_users_email_token ON public.company_users USING btree (email_verification_token) WHERE (email_verification_token IS NOT NULL);


--
-- Name: idx_company_users_password_reset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_users_password_reset ON public.company_users USING btree (password_reset_token) WHERE (password_reset_token IS NOT NULL);


--
-- Name: idx_company_users_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_users_role ON public.company_users USING btree (role);


--
-- Name: idx_employee_permissions_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_permissions_employee ON public.employee_permissions USING btree (employee_id) WHERE (is_active = true);


--
-- Name: idx_employee_permissions_employee_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_permissions_employee_active ON public.employee_permissions USING btree (employee_id, is_active) WHERE (is_active = true);


--
-- Name: idx_employee_permissions_granted_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_permissions_granted_by ON public.employee_permissions USING btree (granted_by);


--
-- Name: idx_employee_permissions_permission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_permissions_permission ON public.employee_permissions USING btree (permission_id) WHERE (is_active = true);


--
-- Name: idx_employee_permissions_unique_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_employee_permissions_unique_active ON public.employee_permissions USING btree (employee_id, permission_id) WHERE (revoked_at IS NULL);


--
-- Name: idx_employees_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_account_id ON public.employees USING btree (account_id);


--
-- Name: idx_employees_auth_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_auth_user_id ON public.employees USING btree (auth_user_id) WHERE (auth_user_id IS NOT NULL);


--
-- Name: idx_employees_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_branch_id ON public.employees USING btree (branch_id) WHERE (branch_id IS NOT NULL);


--
-- Name: idx_employees_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_email ON public.employees USING btree (email);


--
-- Name: idx_employees_email_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_email_lower ON public.employees USING btree (lower((email)::text));


--
-- Name: idx_employees_pharmacy_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_pharmacy_id ON public.employees USING btree (pharmacy_id);


--
-- Name: idx_employees_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_status ON public.employees USING btree (status);


--
-- Name: idx_global_products_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_global_products_active ON public.global_products USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_global_products_barcode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_global_products_barcode ON public.global_products USING btree (barcode) WHERE (barcode IS NOT NULL);


--
-- Name: idx_global_products_brand; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_global_products_brand ON public.global_products USING btree (brand_name);


--
-- Name: idx_global_products_fulltext; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_global_products_fulltext ON public.global_products USING gin (to_tsvector('english'::regconfig, (((((COALESCE(name, ''::character varying))::text || ' '::text) || (COALESCE(generic_name, ''::character varying))::text) || ' '::text) || (COALESCE(brand_name, ''::character varying))::text)));


--
-- Name: idx_global_products_generic; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_global_products_generic ON public.global_products USING btree (generic_name);


--
-- Name: idx_global_products_manufacturer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_global_products_manufacturer ON public.global_products USING btree (manufacturer_name);


--
-- Name: idx_global_products_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_global_products_name ON public.global_products USING gin (to_tsvector('english'::regconfig, (name)::text));


--
-- Name: idx_global_products_therapeutic; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_global_products_therapeutic ON public.global_products USING btree (therapeutic_class);


--
-- Name: idx_global_products_unique_barcode; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_global_products_unique_barcode ON public.global_products USING btree (barcode) WHERE (barcode IS NOT NULL);


--
-- Name: idx_inventory_batches_batch_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_batch_number ON public.inventory_batches USING btree (batch_number);


--
-- Name: idx_inventory_batches_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_branch ON public.inventory_batches USING btree (branch_id);


--
-- Name: idx_inventory_batches_expiring_soon; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_expiring_soon ON public.inventory_batches USING btree (branch_id, expiry_date);


--
-- Name: idx_inventory_batches_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_expiry ON public.inventory_batches USING btree (pharmacy_product_id, expiry_date) WHERE (expiry_date IS NOT NULL);


--
-- Name: idx_inventory_batches_low_qty; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_low_qty ON public.inventory_batches USING btree (pharmacy_product_id, quantity) WHERE (quantity <= (10)::numeric);


--
-- Name: idx_inventory_batches_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_product ON public.inventory_batches USING btree (pharmacy_product_id);


--
-- Name: idx_permissions_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_permissions_category ON public.permissions USING btree (category);


--
-- Name: idx_permissions_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_permissions_key ON public.permissions USING btree (key);


--
-- Name: idx_permissions_module; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_permissions_module ON public.permissions USING btree (module);


--
-- Name: idx_pharmacies_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pharmacies_account_id ON public.pharmacies USING btree (account_id);


--
-- Name: idx_pharmacies_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pharmacies_active ON public.pharmacies USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_pharmacies_license_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_pharmacies_license_number ON public.pharmacies USING btree (license_number) WHERE (license_number IS NOT NULL);


--
-- Name: idx_pharmacy_products_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pharmacy_products_active ON public.pharmacy_products USING btree (pharmacy_id, is_active) WHERE (is_active = true);


--
-- Name: idx_pharmacy_products_global; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pharmacy_products_global ON public.pharmacy_products USING btree (global_product_id);


--
-- Name: idx_pharmacy_products_low_stock; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pharmacy_products_low_stock ON public.pharmacy_products USING btree (pharmacy_id) WHERE ((is_active = true) AND (min_stock_level > (0)::numeric));


--
-- Name: idx_pharmacy_products_pharmacy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pharmacy_products_pharmacy ON public.pharmacy_products USING btree (pharmacy_id);


--
-- Name: idx_pharmacy_products_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pharmacy_products_sku ON public.pharmacy_products USING btree (pharmacy_id, internal_sku) WHERE (internal_sku IS NOT NULL);


--
-- Name: idx_role_permissions_permission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_role_permissions_permission ON public.role_permissions USING btree (permission_id);


--
-- Name: idx_role_permissions_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_role_permissions_role ON public.role_permissions USING btree (role_id);


--
-- Name: idx_roles_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_account ON public.roles USING btree (account_id) WHERE (account_id IS NOT NULL);


--
-- Name: idx_roles_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_active ON public.roles USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_roles_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_name ON public.roles USING btree (name);


--
-- Name: idx_stock_movements_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_movements_batch ON public.stock_movements USING btree (batch_id);


--
-- Name: idx_stock_movements_batch_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_movements_batch_recent ON public.stock_movements USING btree (batch_id, created_at DESC);


--
-- Name: idx_stock_movements_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_movements_created ON public.stock_movements USING btree (created_at DESC);


--
-- Name: idx_stock_movements_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_movements_created_by ON public.stock_movements USING btree (created_by);


--
-- Name: idx_stock_movements_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_movements_reference ON public.stock_movements USING btree (reference_type, reference_id) WHERE (reference_id IS NOT NULL);


--
-- Name: idx_stock_movements_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_movements_type ON public.stock_movements USING btree (movement_type);


--
-- Name: idx_unit_conversions_from_to; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_unit_conversions_from_to ON public.unit_conversions USING btree (global_product_id, from_unit, to_unit);


--
-- Name: idx_unit_conversions_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_unit_conversions_product ON public.unit_conversions USING btree (global_product_id);


--
-- Name: v_company_summary _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.v_company_summary AS
 SELECT c.id,
    c.name,
    c.name_ar,
    c.legal_name,
    c.registration_number,
    c.email,
    c.phone,
    c.website,
    c.address_line1,
    c.address_line2,
    c.city,
    c.state_province,
    c.postal_code,
    c.country,
    c.status,
    c.plan,
    c.trial_ends_at,
    c.subscription_current_period_start,
    c.subscription_current_period_end,
    c.max_accounts,
    c.max_users_per_account,
    c.default_currency,
    c.timezone,
    c.locale,
    c.settings,
    c.logo_url,
    c.primary_color,
    c.secondary_color,
    c.created_at,
    c.updated_at,
    c.deleted_at,
    c.is_active,
    count(DISTINCT a.id) AS total_accounts,
    count(DISTINCT
        CASE
            WHEN (a.status = 'active'::public.account_status) THEN a.id
            ELSE NULL::uuid
        END) AS active_accounts,
    count(DISTINCT cu.id) AS total_users
   FROM ((public.companies c
     LEFT JOIN public.accounts a ON (((a.company_id = c.id) AND (a.deleted_at IS NULL))))
     LEFT JOIN public.company_users cu ON (((cu.company_id = c.id) AND (cu.deleted_at IS NULL) AND (cu.is_active = true))))
  WHERE (c.deleted_at IS NULL)
  GROUP BY c.id;


--
-- Name: company_user_permissions trigger_company_permission_version; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_company_permission_version AFTER INSERT OR UPDATE ON public.company_user_permissions FOR EACH ROW EXECUTE FUNCTION public.trigger_company_permission_version_change();


--
-- Name: employee_permissions trigger_permission_version_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_permission_version_change AFTER INSERT OR UPDATE ON public.employee_permissions FOR EACH ROW EXECUTE FUNCTION public.trigger_increment_permission_version();


--
-- Name: accounts update_accounts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: attendance_records update_attendance_records_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_attendance_records_updated_at BEFORE UPDATE ON public.attendance_records FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: audit_logs update_audit_logs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_audit_logs_updated_at BEFORE UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: branches update_branches_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_branches_updated_at BEFORE UPDATE ON public.branches FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: companies update_companies_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_companies_updated_at BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: company_users update_company_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_company_users_updated_at BEFORE UPDATE ON public.company_users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: employees update_employees_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: global_products update_global_products_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_global_products_updated_at BEFORE UPDATE ON public.global_products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: inventory_batches update_inventory_batches_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_inventory_batches_updated_at BEFORE UPDATE ON public.inventory_batches FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: pharmacies update_pharmacies_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_pharmacies_updated_at BEFORE UPDATE ON public.pharmacies FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: pharmacy_products update_pharmacy_products_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_pharmacy_products_updated_at BEFORE UPDATE ON public.pharmacy_products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: roles update_roles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_roles_updated_at BEFORE UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: accounts accounts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE SET NULL;


--
-- Name: attendance_records attendance_records_adjusted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_adjusted_by_fkey FOREIGN KEY (adjusted_by) REFERENCES public.employees(id);


--
-- Name: attendance_records attendance_records_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: attendance_records attendance_records_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: attendance_records attendance_records_pharmacy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES public.pharmacies(id) ON DELETE CASCADE;


--
-- Name: audit_logs audit_logs_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: audit_logs audit_logs_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.employees(id);


--
-- Name: audit_logs audit_logs_pharmacy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES public.pharmacies(id) ON DELETE CASCADE;


--
-- Name: auth_sessions auth_sessions_replaced_by_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_replaced_by_session_id_fkey FOREIGN KEY (replaced_by_session_id) REFERENCES public.auth_sessions(id);


--
-- Name: branches branches_pharmacy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES public.pharmacies(id) ON DELETE CASCADE;


--
-- Name: company_user_permissions company_user_permissions_company_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_user_permissions
    ADD CONSTRAINT company_user_permissions_company_user_id_fkey FOREIGN KEY (company_user_id) REFERENCES public.company_users(id) ON DELETE CASCADE;


--
-- Name: company_user_permissions company_user_permissions_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_user_permissions
    ADD CONSTRAINT company_user_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.company_users(id);


--
-- Name: company_user_permissions company_user_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_user_permissions
    ADD CONSTRAINT company_user_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE CASCADE;


--
-- Name: company_user_permissions company_user_permissions_revoked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_user_permissions
    ADD CONSTRAINT company_user_permissions_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.company_users(id);


--
-- Name: company_users company_users_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_users
    ADD CONSTRAINT company_users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: employee_permissions employee_permissions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_permissions
    ADD CONSTRAINT employee_permissions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_permissions employee_permissions_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_permissions
    ADD CONSTRAINT employee_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.employees(id);


--
-- Name: employee_permissions employee_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_permissions
    ADD CONSTRAINT employee_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE CASCADE;


--
-- Name: employee_permissions employee_permissions_revoked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_permissions
    ADD CONSTRAINT employee_permissions_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.employees(id);


--
-- Name: employees employees_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: employees employees_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: employees employees_pharmacy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES public.pharmacies(id) ON DELETE CASCADE;


--
-- Name: inventory_batches inventory_batches_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: inventory_batches inventory_batches_pharmacy_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_pharmacy_product_id_fkey FOREIGN KEY (pharmacy_product_id) REFERENCES public.pharmacy_products(id) ON DELETE CASCADE;


--
-- Name: inventory_batches inventory_batches_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.employees(id);


--
-- Name: permissions permissions_parent_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_parent_key_fkey FOREIGN KEY (parent_key) REFERENCES public.permissions(key);


--
-- Name: pharmacies pharmacies_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pharmacies
    ADD CONSTRAINT pharmacies_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE;


--
-- Name: pharmacy_products pharmacy_products_global_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pharmacy_products
    ADD CONSTRAINT pharmacy_products_global_product_id_fkey FOREIGN KEY (global_product_id) REFERENCES public.global_products(id) ON DELETE CASCADE;


--
-- Name: pharmacy_products pharmacy_products_pharmacy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pharmacy_products
    ADD CONSTRAINT pharmacy_products_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES public.pharmacies(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: roles roles_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: stock_movements stock_movements_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.employees(id);


--
-- Name: stock_movements stock_movements_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.inventory_batches(id) ON DELETE CASCADE;


--
-- Name: stock_movements stock_movements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.employees(id);


--
-- Name: unit_conversions unit_conversions_global_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unit_conversions
    ADD CONSTRAINT unit_conversions_global_product_id_fkey FOREIGN KEY (global_product_id) REFERENCES public.global_products(id) ON DELETE CASCADE;


--
-- Name: accounts accounts_can_view_own_accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY accounts_can_view_own_accounts ON public.accounts USING (((company_id = (current_setting('app.current_company_id'::text, true))::uuid) OR (id = (current_setting('app.current_account_id'::text, true))::uuid) OR ((current_setting('app.is_super_admin'::text, true))::boolean = true)));


--
-- Name: pharmacies accounts_can_view_own_pharmacies; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY accounts_can_view_own_pharmacies ON public.pharmacies FOR SELECT USING ((account_id IN ( SELECT accounts.id
   FROM public.accounts
  WHERE (accounts.id = pharmacies.account_id))));


--
-- Name: attendance_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs audit_logs_immutable_no_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_logs_immutable_no_delete ON public.audit_logs FOR DELETE USING (false);


--
-- Name: audit_logs audit_logs_immutable_no_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_logs_immutable_no_update ON public.audit_logs FOR UPDATE USING (false);


--
-- Name: branches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_permissions can_grant_same_pharmacy_permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY can_grant_same_pharmacy_permissions ON public.employee_permissions FOR INSERT WITH CHECK ((employee_id IN ( SELECT employees.id
   FROM public.employees
  WHERE (employees.pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid))));


--
-- Name: employee_permissions can_revoke_permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY can_revoke_permissions ON public.employee_permissions FOR UPDATE USING ((employee_id IN ( SELECT employees.id
   FROM public.employees
  WHERE (employees.pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid))));


--
-- Name: company_user_permissions can_view_same_company_permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY can_view_same_company_permissions ON public.company_user_permissions FOR SELECT USING ((company_user_id IN ( SELECT company_users.id
   FROM public.company_users
  WHERE (company_users.company_id = (current_setting('app.current_company_id'::text, true))::uuid))));


--
-- Name: employee_permissions can_view_same_pharmacy_permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY can_view_same_pharmacy_permissions ON public.employee_permissions FOR SELECT USING ((employee_id IN ( SELECT employees.id
   FROM public.employees
  WHERE (employees.pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid))));


--
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Name: company_user_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_user_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: company_users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

--
-- Name: company_users company_users_can_manage_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY company_users_can_manage_same_company ON public.company_users USING ((company_id = (current_setting('app.current_company_id'::text, true))::uuid));


--
-- Name: employee_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: employees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;

--
-- Name: pharmacies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pharmacies ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance_records pharmacies_can_insert_own_attendance; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_insert_own_attendance ON public.attendance_records FOR INSERT WITH CHECK ((pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid));


--
-- Name: audit_logs pharmacies_can_insert_own_audit_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_insert_own_audit_logs ON public.audit_logs FOR INSERT WITH CHECK ((pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid));


--
-- Name: inventory_batches pharmacies_can_insert_own_batches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_insert_own_batches ON public.inventory_batches FOR INSERT WITH CHECK ((pharmacy_product_id IN ( SELECT pharmacy_products.id
   FROM public.pharmacy_products
  WHERE (pharmacy_products.pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid))));


--
-- Name: stock_movements pharmacies_can_insert_own_movements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_insert_own_movements ON public.stock_movements FOR INSERT WITH CHECK ((batch_id IN ( SELECT inventory_batches.id
   FROM public.inventory_batches
  WHERE (inventory_batches.pharmacy_product_id IN ( SELECT pharmacy_products.id
           FROM public.pharmacy_products
          WHERE (pharmacy_products.pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid))))));


--
-- Name: employees pharmacies_can_manage_own_employees; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_manage_own_employees ON public.employees USING ((pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid));


--
-- Name: pharmacy_products pharmacies_can_manage_own_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_manage_own_products ON public.pharmacy_products USING ((pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid));


--
-- Name: attendance_records pharmacies_can_update_own_attendance; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_update_own_attendance ON public.attendance_records FOR UPDATE USING ((pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid));


--
-- Name: attendance_records pharmacies_can_view_own_attendance; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_view_own_attendance ON public.attendance_records FOR SELECT USING ((pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid));


--
-- Name: audit_logs pharmacies_can_view_own_audit_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_view_own_audit_logs ON public.audit_logs FOR SELECT USING ((pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid));


--
-- Name: inventory_batches pharmacies_can_view_own_batches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_view_own_batches ON public.inventory_batches FOR SELECT USING ((pharmacy_product_id IN ( SELECT pharmacy_products.id
   FROM public.pharmacy_products
  WHERE (pharmacy_products.pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid))));


--
-- Name: branches pharmacies_can_view_own_branches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_view_own_branches ON public.branches USING ((pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid));


--
-- Name: stock_movements pharmacies_can_view_own_movements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_can_view_own_movements ON public.stock_movements FOR SELECT USING ((batch_id IN ( SELECT inventory_batches.id
   FROM public.inventory_batches
  WHERE (inventory_batches.pharmacy_product_id IN ( SELECT pharmacy_products.id
           FROM public.pharmacy_products
          WHERE (pharmacy_products.pharmacy_id = (current_setting('app.current_pharmacy_id'::text, true))::uuid))))));


--
-- Name: pharmacy_products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pharmacy_products ENABLE ROW LEVEL SECURITY;

--
-- Name: roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: company_users super_admins_can_manage_all_company_users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY super_admins_can_manage_all_company_users ON public.company_users USING (((current_setting('app.is_super_admin'::text, true))::boolean = true));


--
-- Name: companies super_admins_can_manage_companies; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY super_admins_can_manage_companies ON public.companies USING ((((current_setting('app.is_super_admin'::text, true))::boolean = true) OR (id = (current_setting('app.current_company_id'::text, true))::uuid)));


--
-- Name: roles system_roles_visible_to_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY system_roles_visible_to_all ON public.roles FOR SELECT USING (((account_id IS NULL) OR (account_id = (current_setting('app.current_account_id'::text, true))::uuid)));


--
-- PostgreSQL database dump complete
--

\unrestrict AOpwBPkyfYgAq40aRMtaNXN1NYXMg0VZgtSe0Hfa82Wamb0ddMa0ZGYWpZXM35y

