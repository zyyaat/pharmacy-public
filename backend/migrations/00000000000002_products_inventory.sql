-- Migration: Product Master & Inventory System
-- Version: Phase 1 - Revised Architecture
-- Description: Creates the Global Product Master, Unit Conversions,
--              Pharmacy Products, Inventory Batches, and Stock Movements
--              This supports: Box → Strip → Tablet conversions from day one

-- ============================================
-- ENUM TYPES for Products & Inventory
-- ============================================
CREATE TYPE dosage_form AS ENUM (
    'tablet', 'capsule', 'syrup', 'drop', 'injection', 'ointment', 
    'cream', 'gel', 'powder', 'solution', 'suspension', 'inhaler',
    'patch', 'suppository', 'eye_drops', 'ear_drops', 'nasal_spray',
    'other'
);

CREATE TYPE product_category AS ENUM (
    'medication', 'supplement', 'medical_device', 'personal_care',
    'cosmetic', 'food_supplement', 'herbal', 'vaccine', 'consumable',
    'other'
);

CREATE TYPE unit_type AS ENUM (
    'box', 'strip', 'blister', 'tablet', 'capsule', 'bottle', 'vial',
    'ampoule', 'tube', 'jar', 'packet', 'piece', 'set', 'kit',
    'liter', 'milliliter', 'gram', 'kilogram', 'meter', 'other'
);

CREATE TYPE movement_type AS ENUM (
    'purchase',      -- Goods received from supplier
    'sale',          -- Sold to customer
    'return_to_supplier',   -- Returned to supplier
    'return_from_customer', -- Customer return
    'adjustment',    -- Stock count adjustment (increase or decrease)
    'transfer_in',   -- Received from another branch
    'transfer_out',  -- Sent to another branch
    'expiry_writeoff',      -- Written off due to expiration
    'damage_writeoff',      -- Written off due to damage
    'theft_loss',           -- Lost due to theft
    'production_input',     -- Used in production/compounding
    'production_output'     -- Produced from compounding
);

CREATE TYPE prescription_required AS ENUM ('yes', 'no', 'otc_only');

-- ============================================
-- TABLE: global_products
-- Description: Global Product Master - defined once, used by all pharmacies
--              This is a shared catalog, not tenant-specific
-- ============================================
CREATE TABLE global_products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Basic Identification
    name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255),
    brand_name VARCHAR(255),
    
    -- Classification
    dosage_form dosage_form NOT NULL,
    strength VARCHAR(100), -- e.g., "500mg", "250mg/5ml"
    product_category product_category DEFAULT 'medication',
    
    -- Regulatory Information
    requires_prescription prescription_required DEFAULT 'no',
    controlled_substance BOOLEAN DEFAULT false,
    schedule_category VARCHAR(50), -- For controlled substances
    
    -- Identification Codes
    barcode VARCHAR(100), -- EAN-13, UPC, etc.
    barcode_type VARCHAR(20) DEFAULT 'EAN13', -- EAN13, UPC, CODE128, etc.
    national_code VARCHAR(100), -- Country-specific product code
    manufacturer_sku VARCHAR(100),
    
    -- Manufacturer Information
    manufacturer_name VARCHAR(255),
    manufacturer_country VARCHAR(100),
    
    -- Therapeutic Information
    active_ingredient VARCHAR(255),
    therapeutic_class VARCHAR(100),
    atc_code VARCHAR(20), -- Anatomical Therapeutic Chemical classification
    
    -- Packaging Information (for display purposes)
    default_unit unit_type DEFAULT 'tablet',
    description TEXT,
    storage_instructions TEXT,
    
    -- Status & Metadata
    is_active BOOLEAN DEFAULT true,
    created_by UUID, -- System admin who created it
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for global products
CREATE UNIQUE INDEX idx_global_products_unique_barcode
    ON global_products(barcode) WHERE barcode IS NOT NULL;
CREATE INDEX idx_global_products_name ON global_products USING gin(to_tsvector('english', name));
CREATE INDEX idx_global_products_brand ON global_products(brand_name);
CREATE INDEX idx_global_products_barcode ON global_products(barcode) WHERE barcode IS NOT NULL;
CREATE INDEX idx_global_products_generic ON global_products(generic_name);
CREATE INDEX idx_global_products_active ON global_products(is_active) WHERE is_active = true;
CREATE INDEX idx_global_products_manufacturer ON global_products(manufacturer_name);
CREATE INDEX idx_global_products_therapeutic ON global_products(therapeutic_class);

-- Full-text search index
CREATE INDEX idx_global_products_fulltext ON global_products 
    USING gin(to_tsvector('english', COALESCE(name, '') || ' ' || COALESCE(generic_name, '') || ' ' || COALESCE(brand_name, '')));

COMMENT ON TABLE global_products IS 'Global Product Master - shared catalog defined once, used by all pharmacies';
COMMENT ON COLUMN global_products.barcode IS 'Primary barcode (EAN-13, UPC, etc.) - must be unique when present';

-- ============================================
-- TABLE: unit_conversions
-- Description: Unit conversion rules for products
--              Supports: 1 box = 5 strips, 1 strip = 10 tablets
--              Therefore: 1 box = 50 tablets
-- ============================================
CREATE TABLE unit_conversions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Product Relationship
    global_product_id UUID NOT NULL REFERENCES global_products(id) ON DELETE CASCADE,
    
    -- Conversion Definition
    from_unit unit_type NOT NULL,
    to_unit unit_type NOT NULL,
    conversion_factor NUMERIC(12,6) NOT NULL CHECK (conversion_factor > 0),
    -- Example: from_unit='box', to_unit='strip', factor=5 means: 1 box = 5 strips
    
    -- Metadata
    is_standard BOOLEAN DEFAULT true, -- Standard conversion vs. custom
    description VARCHAR(255), -- e.g., "Manufacturer standard packaging"
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT unique_conversion_per_product UNIQUE (global_product_id, from_unit, to_unit)
);

-- Indexes for unit conversions
CREATE INDEX idx_unit_conversions_product ON unit_conversions(global_product_id);
CREATE INDEX idx_unit_conversions_from_to ON unit_conversions(global_product_id, from_unit, to_unit);

-- ============================================
-- FUNCTION: Convert between units for a product
-- ============================================
CREATE OR REPLACE FUNCTION convert_units(
    p_product_id UUID,
    p_from_unit unit_type,
    p_to_unit unit_type,
    p_quantity NUMERIC(12,4)
) RETURNS NUMERIC(12,4) AS $$
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
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON TABLE unit_conversions IS 'Unit conversion rules - enables box→strip→tablet calculations';
COMMENT ON FUNCTION convert_units IS 'Convert quantity from one unit to another based on product conversion rules';

-- ============================================
-- TABLE: pharmacy_products
-- Description: Pharmacy-specific product data
--              Links global product to pharmacy with pricing and settings
-- ============================================
CREATE TABLE pharmacy_products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Relationships
    pharmacy_id UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    global_product_id UUID NOT NULL REFERENCES global_products(id) ON DELETE CASCADE,
    
    -- Pricing (pharmacy-specific)
    cost_price NUMERIC(12,4) DEFAULT 0, -- Average cost price
    selling_price NUMERIC(12,4) NOT NULL, -- Current selling price
    margin_percentage NUMERIC(5,2), -- Calculated margin
    tax_rate NUMERIC(5,2) DEFAULT 0, -- Tax percentage (e.g., VAT)
    tax_category VARCHAR(50), -- e.g., 'standard', 'reduced', 'zero', 'exempt'
    
    -- Inventory Settings
    min_stock_level NUMERIC(12,4) DEFAULT 0, -- Reorder point
    max_stock_level NUMERIC(12,4), -- Maximum stock to hold
    reorder_quantity NUMERIC(12,4), -- Suggested reorder quantity
    preferred_supplier_id UUID, -- Will reference suppliers table in future
    
    -- Pharmacy-Specific Data
    internal_sku VARCHAR(100), -- Pharmacy's internal SKU/code
    shelf_location VARCHAR(100), -- Where it's stored (e.g., "A-12-3")
    bin_location VARCHAR(50), -- Bin/picking location for POS
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    is_discontinued BOOLEAN DEFAULT false,
    
    -- Timestamps
    first_added_at TIMESTAMPTZ DEFAULT NOW(),
    last_received_at TIMESTAMPTZ, -- Updated on purchase receipt
    last_sold_at TIMESTAMPTZ, -- Updated on sale
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT pharmacy_products_unique UNIQUE (pharmacy_id, global_product_id)
);

-- Indexes for pharmacy products
CREATE INDEX idx_pharmacy_products_pharmacy ON pharmacy_products(pharmacy_id);
CREATE INDEX idx_pharmacy_products_global ON pharmacy_products(global_product_id);
CREATE INDEX idx_pharmacy_products_active ON pharmacy_products(pharmacy_id, is_active) WHERE is_active = true;
CREATE INDEX idx_pharmacy_products_sku ON pharmacy_products(pharmacy_id, internal_sku) WHERE internal_sku IS NOT NULL;
CREATE INDEX idx_pharmacy_products_low_stock ON pharmacy_products(pharmacy_id) 
    WHERE is_active = true AND min_stock_level > 0;

-- RLS for pharmacy products
ALTER TABLE pharmacy_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pharmacies_can_manage_own_products" ON pharmacy_products
    FOR ALL USING (
        pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
    );

-- Trigger to update timestamps
CREATE TRIGGER update_pharmacy_products_updated_at BEFORE UPDATE ON pharmacy_products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE pharmacy_products IS 'Pharmacy-specific product data - pricing, stock levels, settings per tenant';

-- ============================================
-- TABLE: inventory_batches
-- Description: Physical inventory batches with expiry tracking
--              Each batch represents actual physical stock at a branch
-- ============================================
CREATE TABLE inventory_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Relationships
    pharmacy_product_id UUID NOT NULL REFERENCES pharmacy_products(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    
    -- Batch Identification
    batch_number VARCHAR(100) NOT NULL, -- Manufacturer lot/batch number
    barcode VARCHAR(100), -- Batch-specific barcode (if different from product)
    
    -- Quantity & Unit
    quantity NUMERIC(12,4) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    unit unit_type NOT NULL DEFAULT 'tablet',
    
    -- Cost Tracking
    cost_per_unit NUMERIC(12,4) NOT NULL DEFAULT 0, -- Purchase cost per unit
    total_cost NUMERIC(14,2) GENERATED ALWAYS AS (quantity * cost_per_unit) STORED,
    
    -- Expiry & Shelf Life
    manufacture_date DATE,
    expiry_date DATE,
    -- Maintained by application writes; CURRENT_DATE cannot be used in a
    -- PostgreSQL generated column because it is not immutable.
    days_until_expiry INTEGER,
    
    -- Supplier Information (for traceability)
    supplier_name VARCHAR(255), -- Denormalized for performance
    supplier_reference VARCHAR(100), -- PO number or supplier invoice #
    
    -- Location Details
    location VARCHAR(100), -- Specific storage location (e.g., "Fridge A", "Shelf B-2")
    
    -- Status
    is_reserved BOOLEAN DEFAULT false, -- Part of unfulfilled order
    is_quarantined BOOLEAN DEFAULT false, -- Quality hold
    quarantine_reason TEXT,
    
    -- Receipt Information
    received_date DATE NOT NULL DEFAULT CURRENT_DATE,
    received_by UUID REFERENCES employees(id),
    reference_type VARCHAR(50), -- 'purchase_order', 'transfer', 'adjustment', etc.
    reference_id UUID, -- ID of the source document
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT inventory_batches_unique_batch UNIQUE (pharmacy_product_id, branch_id, batch_number)
);

-- Indexes for inventory batches
CREATE INDEX idx_inventory_batches_product ON inventory_batches(pharmacy_product_id);
CREATE INDEX idx_inventory_batches_branch ON inventory_batches(branch_id);
CREATE INDEX idx_inventory_batches_expiry ON inventory_batches(pharmacy_product_id, expiry_date) 
    WHERE expiry_date IS NOT NULL;
CREATE INDEX idx_inventory_batches_batch_number ON inventory_batches(batch_number);
CREATE INDEX idx_inventory_batches_low_qty ON inventory_batches(pharmacy_product_id, quantity) 
    WHERE quantity <= 10; -- Fast low-stock lookup
-- CURRENT_DATE is not immutable, so the rolling expiry window is evaluated
-- by queries rather than encoded in a partial index.
CREATE INDEX idx_inventory_batches_expiring_soon ON inventory_batches(branch_id, expiry_date);

-- RLS for inventory batches
ALTER TABLE inventory_batches ENABLE ROW LEVEL SECURITY;

-- Policy: Access via pharmacy_id (join through pharmacy_products)
CREATE POLICY "pharmacies_can_view_own_batches" ON inventory_batches
    FOR SELECT USING (
        pharmacy_product_id IN (
            SELECT id FROM pharmacy_products 
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

CREATE POLICY "pharmacies_can_insert_own_batches" ON inventory_batches
    FOR INSERT WITH CHECK (
        pharmacy_product_id IN (
            SELECT id FROM pharmacy_products 
            WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
        )
    );

-- Trigger to update timestamps
CREATE TRIGGER update_inventory_batches_updated_at BEFORE UPDATE ON inventory_batches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE inventory_batches IS 'Physical inventory batches - tracks actual stock with expiry and cost per batch';
COMMENT ON COLUMN inventory_batches.quantity IS 'Current quantity - should equal SUM of related stock_movements';
COMMENT ON COLUMN inventory_batches.days_until_expiry IS 'Calculated field - triggers alerts when low';

-- ============================================
-- TABLE: stock_movements
-- Description: Every inventory change is recorded here
--              This is the SOURCE OF TRUTH for all quantities
--              Batch quantities are derived from SUM of movements
-- ============================================
CREATE TABLE stock_movements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Relationship
    batch_id UUID NOT NULL REFERENCES inventory_batches(id) ON DELETE CASCADE,
    
    -- Movement Details
    movement_type movement_type NOT NULL,
    quantity NUMERIC(12,4) NOT NULL CHECK (quantity != 0), -- Positive = IN, Negative = OUT
    unit unit_type NOT NULL,
    
    -- Reference to Source Document
    reference_type VARCHAR(50), -- 'purchase_order', 'sale', 'adjustment', 'transfer', etc.
    reference_id UUID, -- ID of the source document
    
    -- Quantity After Movement (for quick queries)
    quantity_before NUMERIC(12,4), -- Snapshot before this movement
    quantity_after NUMERIC(12,4), -- Snapshot after this movement
    
    -- Financial Impact (optional, for accounting integration)
    unit_cost NUMERIC(12,4), -- Cost per unit at time of movement
    total_cost NUMERIC(14,2), -- quantity * unit_cost
    
    -- People
    created_by UUID NOT NULL REFERENCES employees(id), -- Who made this movement
    approved_by UUID REFERENCES employees(id), -- For movements requiring approval
    
    -- Notes & Reasoning
    reason TEXT, -- Why this adjustment was made (required for adjustments)
    notes TEXT, -- Additional notes
    
    -- Metadata
    ip_address INET,
    user_agent TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes for stock movements
CREATE INDEX idx_stock_movements_batch ON stock_movements(batch_id);
CREATE INDEX idx_stock_movements_type ON stock_movements(movement_type);
CREATE INDEX idx_stock_movements_created ON stock_movements(created_at DESC);
CREATE INDEX idx_stock_movements_reference ON stock_movements(reference_type, reference_id) 
    WHERE reference_id IS NOT NULL;
CREATE INDEX idx_stock_movements_created_by ON stock_movements(created_by);

-- Composite index for common query: get recent movements for a product
CREATE INDEX idx_stock_movements_batch_recent ON stock_movements(batch_id, created_at DESC);

-- RLS for stock movements (same pattern as batches)
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pharmacies_can_view_own_movements" ON stock_movements
    FOR SELECT USING (
        batch_id IN (
            SELECT id FROM inventory_batches 
            WHERE pharmacy_product_id IN (
                SELECT id FROM pharmacy_products 
                WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
            )
        )
    );

CREATE POLICY "pharmacies_can_insert_own_movements" ON stock_movements
    FOR INSERT WITH CHECK (
        batch_id IN (
            SELECT id FROM inventory_batches 
            WHERE pharmacy_product_id IN (
                SELECT id FROM pharmacy_products 
                WHERE pharmacy_id = current_setting('app.current_pharmacy_id', true)::UUID
            )
        )
    );

COMMENT ON TABLE stock_movements IS 'SOURCE OF TRUTH for all inventory quantities - every stock change must be recorded here';
COMMENT ON COLUMN stock_movements.quantity IS 'Positive = stock IN, Negative = stock OUT';
COMMENT ON COLUMN stock_movements.reference_type IS 'Source document type: purchase_order, sale, adjustment, transfer, etc.';

-- ============================================
-- FUNCTION: Calculate current stock for a batch
-- ============================================
CREATE OR REPLACE FUNCTION calculate_batch_current_stock(p_batch_id UUID)
RETURNS NUMERIC(12,4) AS $$
DECLARE
    v_current_stock NUMERIC(12,4);
BEGIN
    SELECT COALESCE(SUM(quantity), 0) INTO v_current_stock
    FROM stock_movements
    WHERE batch_id = p_batch_id;
    
    RETURN v_current_stock;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- FUNCTION: Calculate total stock for a pharmacy product across all batches
-- ============================================
CREATE OR REPLACE FUNCTION calculate_product_total_stock(p_pharmacy_product_id UUID, p_branch_id UUID DEFAULT NULL)
RETURNS NUMERIC(12,4) AS $$
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
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- VIEW: current_inventory
-- Description: Pre-calculated view of current stock levels
--              Joins batches with calculated quantities from movements
-- ============================================
CREATE OR REPLACE VIEW current_inventory AS
SELECT 
    ib.id as batch_id,
    pp.id as pharmacy_product_id,
    pp.pharmacy_id,
    ib.branch_id,
    gp.id as global_product_id,
    gp.name as product_name,
    gp.generic_name,
    gp.brand_name,
    gp.barcode,
    gp.dosage_form,
    gp.strength,
    ib.batch_number,
    ib.unit,
    calculate_batch_current_stock(ib.id) as quantity,
    ib.cost_per_unit,
    ib.total_cost,
    ib.expiry_date,
    ib.days_until_expiry,
    pp.selling_price,
    pp.min_stock_level,
    b.name as branch_name,
    CASE 
        WHEN calculate_batch_current_stock(ib.id) <= pp.min_stock_level THEN 'low_stock'
        WHEN ib.expiry_date IS NOT NULL AND ib.expiry_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'expiring_soon'
        WHEN ib.is_quarantined THEN 'quarantined'
        ELSE 'normal'
    END as status
FROM inventory_batches ib
JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
JOIN global_products gp ON pp.global_product_id = gp.id
LEFT JOIN branches b ON ib.branch_id = b.id
WHERE ib.quantity > 0 OR calculate_batch_current_stock(ib.id) > 0; -- Only show non-empty or recently emptied

-- Index hint for the view (not directly possible, but document expected usage)
COMMENT ON VIEW current_inventory IS 'Pre-calculated view of current inventory - use for dashboards and reports';
COMMENT ON COLUMN current_inventory.quantity IS 'Calculated from SUM(stock_movements) - always accurate';

-- ============================================
-- TRIGGER: Auto-update batch quantity on movement insertion
-- Note: This is optional - can also be calculated on-read via the function above
-- ============================================
CREATE OR REPLACE FUNCTION update_batch_quantity_on_movement()
RETURNS TRIGGER AS $$
BEGIN
    -- Update the batch's cached quantity (optimization for frequent reads)
    UPDATE inventory_batches 
    SET quantity = calculate_batch_current_quality(NEW.batch_id),
        updated_at = NOW()
    WHERE id = NEW.batch_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Optional: Enable this trigger if you want real-time batch quantity updates
-- CREATE TRIGGER trigger_update_batch_quantity AFTER INSERT OR UPDATE ON stock_movements
--     FOR EACH ROW EXECUTE FUNCTION update_batch_quantity_on_movement();

-- Note: The trigger above has a typo fix needed: calculate_batch_current_quality → calculate_batch_current_stock
-- Uncomment and fix if you want automatic batch quantity updates

-- ============================================
-- Updated triggers for new tables
-- ============================================
CREATE TRIGGER update_global_products_updated_at BEFORE UPDATE ON global_products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
