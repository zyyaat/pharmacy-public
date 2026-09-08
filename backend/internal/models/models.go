// Package models defines data structures for Pharmacy OS
// Phase 1 - Revised Architecture: Global Product Master + Unit Conversions + Inventory Batches + Stock Movements
package models

import (
	"time"
)

// ============================================
// Foundation Models (Accounts, Tenancy)
// ============================================

// Account represents the top-level tenant account (pays the bill)
type Account struct {
	ID                  string     `json:"id"`
	CompanyName         string     `json:"company_name"`
	ContactEmail        string     `json:"contact_email"`
	ContactPhone        *string    `json:"contact_phone,omitempty"`
	BillingAddress      *string    `json:"billing_address,omitempty"`
	Status              string     `json:"status"` // active, suspended, cancelled, trial
	TrialEndsAt         *time.Time `json:"trial_ends_at,omitempty"`
	SubscriptionPlan    string     `json:"subscription_plan"` // free, professional, enterprise
	DefaultCurrency     string     `json:"default_currency"`
	Timezone            string     `json:"timezone"`
	Locale              string     `json:"locale"`
	Settings            map[string]interface{} `json:"settings,omitempty"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
}

// Pharmacy represents a pharmacy tenant (belongs to an account)
type Pharmacy struct {
	ID                       string     `json:"id"`
	AccountID                string     `json:"account_id"`
	Name                     string     `json:"name"`
	LegalName                *string    `json:"legal_name,omitempty"`
	LicenseNumber            *string    `json:"license_number,omitempty"`
	TaxID                    *string    `json:"tax_id,omitempty"`
	Email                    *string    `json:"email,omitempty"`
	Phone                    *string    `json:"phone,omitempty"`
	Website                  *string    `json:"website,omitempty"`
	AddressLine1             *string    `json:"address_line1,omitempty"`
	AddressLine2             *string    `json:"address_line2,omitempty"`
	City                     *string    `json:"city,omitempty"`
	StateProvince            *string    `json:"state_province,omitempty"`
	PostalCode               *string    `json:"postal_code,omitempty"`
	Country                  *string    `json:"country,omitempty"`
	IsMainBranch             bool       `json:"is_main_branch"`
	DefaultBranchID          *string    `json:"default_branch_id,omitempty"`
	Currency                 *string    `json:"currency,omitempty"`
	AutoExpiryAlertDays      int        `json:"auto_expiry_alert_days"`
	LowStockThreshold        int        `json:"low_stock_threshold"`
	EnableBatchTracking      bool       `json:"enable_batch_tracking"`
	IsActive                 bool       `json:"is_active"`
	CreatedAt                time.Time  `json:"created_at"`
	UpdatedAt                time.Time  `json:"updated_at"`
}

// Branch represents a sub-branch of a pharmacy
type Branch struct {
	ID           string     `json:"id"`
	PharmacyID   string     `json:"pharmacy_id"`
	Name         string     `json:"name"`
	Code         *string    `json:"code,omitempty"`
	Phone        *string    `json:"phone,omitempty"`
	Email        *string    `json:"email,omitempty"`
	AddressLine1 *string    `json:"address_line1,omitempty"`
	AddressLine2 *string    `json:"address_line2,omitempty"`
	City         *string    `json:"city,omitempty"`
	StateProvince *string   `json:"state_province,omitempty"`
	PostalCode   *string    `json:"postal_code,omitempty"`
	Country      *string    `json:"country,omitempty"`
	ManagerEmployeeID *string `json:"manager_employee_id,omitempty"`
	IsActive     bool       `json:"is_active"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

// Employee represents a pharmacy employee (authentication is owned by the Go API)
type Employee struct {
	ID                   string     `json:"id"`
	AccountID            string     `json:"account_id"`
	PharmacyID           string     `json:"pharmacy_id"`
	BranchID             *string    `json:"branch_id,omitempty"`
	AuthUserID           *string    `json:"auth_user_id,omitempty"` // Legacy provider identifier; unused by Go auth
	Email                string     `json:"email"`
	FirstName            string     `json:"first_name"`
	LastName             string     `json:"last_name"`
	DisplayName          *string    `json:"display_name,omitempty"`
	Phone                *string    `json:"phone,omitempty"`
	Address              *string    `json:"address,omitempty"`
	EmergencyContactName *string    `json:"emergency_contact_name,omitempty"`
	EmergencyContactPhone *string   `json:"emergency_contact_phone,omitempty"`
	EmployeeIDInternal   *string    `json:"employee_id_internal,omitempty"`
	JobTitle             *string    `json:"job_title,omitempty"`
	Department           *string    `json:"department,omitempty"`
	HireDate             *time.Time `json:"hire_date,omitempty"`
	TerminationDate      *time.Time `json:"termination_date,omitempty"`
	BaseSalary           *float64   `json:"base_salary,omitempty"`
	Status               string     `json:"status"` // active, inactive, on_leave, terminated
	PermissionVersion    int        `json:"permission_version"`
	AvatarURL            *string    `json:"avatar_url,omitempty"`
	Preferences          map[string]interface{} `json:"preferences,omitempty"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

// ============================================
// Product Models (Global Product Master)
// ============================================

// DosageForm enum values
const (
	DosageFormTablet    = "tablet"
	DosageFormCapsule   = "capsule"
	DosageFormSyrup     = "syrup"
	DosageFormDrop      = "drop"
	DosageFormInjection = "injection"
	DosageFormOintment  = "ointment"
	DosageFormCream     = "cream"
	DosageFormGel       = "gel"
	DosageFormPowder    = "powder"
	DosageFormSolution  = "solution"
	DosageFormSuspension = "suspension"
	DosageFormInhaler   = "inhaler"
	DosageFormPatch     = "patch"
	DosageFormSuppository = "suppository"
	DosageFormEyeDrops  = "eye_drops"
	DosageFormEarDrops  = "ear_drops"
	DosageFormNasalSpray = "nasal_spray"
	DosageFormOther     = "other"
)

// UnitType enum values for inventory units
const (
	UnitBox      = "box"
	UnitStrip    = "strip"
	UnitBlister  = "blister"
	UnitTablet   = "tablet"
	UnitCapsule  = "capsule"
	UnitBottle   = "bottle"
	UnitVial     = "vial"
	UnitAmpoule  = "ampoule"
	UnitTube     = "tube"
	UnitJar      = "jar"
	UnitPacket   = "packet"
	UnitPiece    = "piece"
	UnitSet      = "set"
	UnitKit      = "kit"
	UnitLiter    = "liter"
	UnitMilliliter = "milliliter"
	UnitGram     = "gram"
	UnitKilogram = "kilogram"
	UnitMeter    = "meter"
	UnitOther    = "other"
)

// GlobalProduct represents a product in the global catalog (shared across all pharmacies)
type GlobalProduct struct {
	ID                   string     `json:"id"`
	Name                 string     `json:"name"`
	GenericName          *string    `json:"generic_name,omitempty"`
	BrandName            *string    `json:"brand_name,omitempty"`
	DosageForm           string     `json:"dosage_form"`
	Strength             *string    `json:"strength,omitempty"`
	ProductCategory      string     `json:"product_category"`
	RequiresPrescription string     `json:"requires_prescription"` // yes, no, otc_only
	ControlledSubstance  bool       `json:"controlled_substance"`
	ScheduleCategory     *string    `json:"schedule_category,omitempty"`
	Barcode              *string    `json:"barcode,omitempty"`
	BarcodeType          *string    `json:"barcode_type,omitempty"`
	NationalCode         *string    `json:"national_code,omitempty"`
	ManufacturerSKU      *string    `json:"manufacturer_sku,omitempty"`
	ManufacturerName     *string    `json:"manufacturer_name,omitempty"`
	ManufacturerCountry  *string    `json:"manufacturer_country,omitempty"`
	ActiveIngredient      *string    `json:"active_ingredient,omitempty"`
	TherapeuticClass     *string    `json:"therapeutic_class,omitempty"`
	ATCCode              *string    `json:"atc_code,omitempty"`
	DefaultUnit          string     `json:"default_unit"`
	Description          *string    `json:"description,omitempty"`
	StorageInstructions  *string    `json:"storage_instructions,omitempty"`
	IsActive             bool       `json:"is_active"`
	CreatedBy            *string    `json:"created_by,omitempty"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

// UnitConversion represents unit conversion rules for a product
// Example: 1 box = 5 strips, 1 strip = 10 tablets → 1 box = 50 tablets
type UnitConversion struct {
	ID               string    `json:"id"`
	GlobalProductID  string    `json:"global_product_id"`
	FromUnit         string    `json:"from_unit"`
	ToUnit           string    `json:"to_unit"`
	ConversionFactor float64   `json:"conversion_factor"` // e.g., 5.0 means 1 from_unit = 5 to_units
	IsStandard       bool      `json:"is_standard"`
	Description      *string   `json:"description,omitempty"`
	CreatedAt        time.Time `json:"created_at"`
}

// PharmacyProduct represents a pharmacy's specific product data (pricing, stock levels, etc.)
type PharmacyProduct struct {
	ID                   string     `json:"id"`
	PharmacyID           string     `json:"pharmacy_id"`
	GlobalProductID      string     `json:"global_product_id"`
	CostPrice            float64    `json:"cost_price"`
	SellingPrice         float64    `json:"selling_price"`
	MarginPercentage     *float64   `json:"margin_percentage,omitempty"`
	TaxRate              float64    `json:"tax_rate"`
	TaxCategory          *string    `json:"tax_category,omitempty"`
	MinStockLevel        float64    `json:"min_stock_level"`
	MaxStockLevel        *float64   `json:"max_stock_level,omitempty"`
	ReorderQuantity      *float64   `json:"reorder_quantity,omitempty"`
	PreferredSupplierID  *string    `json:"preferred_supplier_id,omitempty"`
	InternalSKU          *string    `json:"internal_sku,omitempty"`
	ShelfLocation        *string    `json:"shelf_location,omitempty"`
	BinLocation          *string    `json:"bin_location,omitempty"`
	IsActive             bool       `json:"is_active"`
	IsDiscontinued       bool       `json:"is_discontinued"`
	FirstAddedAt         time.Time  `json:"first_added_at"`
	LastReceivedAt       *time.Time `json:"last_received_at,omitempty"`
	LastSoldAt           *time.Time `json:"last_sold_at,omitempty"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
	
	// Joined fields (not in DB, populated via queries)
	GlobalProduct *GlobalProduct `json:"global_product,omitempty"`
}

// ============================================
// Inventory Models (Batches & Movements)
// ============================================

// MovementType enum values
const (
	MovementPurchase           = "purchase"
	MovementSale               = "sale"
	MovementReturnToSupplier   = "return_to_supplier"
	MovementReturnFromCustomer = "return_from_customer"
	MovementAdjustment         = "adjustment"
	MovementTransferIn         = "transfer_in"
	MovementTransferOut        = "transfer_out"
	MovementExpiryWriteoff     = "expiry_writeoff"
	MovementDamageWriteoff     = "damage_writeoff"
	MovementTheftLoss          = "theft_loss"
	MovementProductionInput    = "production_input"
	MovementProductionOutput   = "production_output"
)

// InventoryBatch represents a physical batch of products at a branch
type InventoryBatch struct {
	ID                string     `json:"id"`
	PharmacyProductID string     `json:"pharmacy_product_id"`
	BranchID          string     `json:"branch_id"`
	BatchNumber       string     `json:"batch_number"`
	Barcode           *string    `json:"barcode,omitempty"`
	Quantity          float64    `json:"quantity"`
	Unit              string     `json:"unit"`
	CostPerUnit       float64    `json:"cost_per_unit"`
	TotalCost         float64    `json:"total_cost"`
	ManufactureDate   *time.Time `json:"manufacture_date,omitempty"`
	ExpiryDate        *time.Time `json:"expiry_date,omitempty"`
	DaysUntilExpiry   *int       `json:"days_until_expiry,omitempty"`
	SupplierName      *string    `json:"supplier_name,omitempty"`
	SupplierReference *string    `json:"supplier_reference,omitempty"`
	Location          *string    `json:"location,omitempty"`
	IsReserved        bool       `json:"is_reserved"`
	IsQuarantined     bool       `json:"is_quarantined"`
	QuarantineReason  *string    `json:"quarantine_reason,omitempty"`
	ReceivedDate      time.Time  `json:"received_date"`
	ReceivedBy        *string    `json:"received_by,omitempty"`
	ReferenceType     *string    `json:"reference_type,omitempty"`
	ReferenceID       *string    `json:"reference_id,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
	
	// Joined fields
	PharmacyProduct *PharmacyProduct `json:"pharmacy_product,omitempty"`
	GlobalProduct  *GlobalProduct   `json:"global_product,omitempty"`
	Branch         *Branch          `json:"branch,omitempty"`
}

// StockMovement represents every inventory change (SOURCE OF TRUTH for quantities)
type StockMovement struct {
	ID              string     `json:"id"`
	BatchID         string     `json:"batch_id"`
	MovementType    string     `json:"movement_type"`
	Quantity        float64    `json:"quantity"` // Positive = IN, Negative = OUT
	Unit            string     `json:"unit"`
	ReferenceType   *string    `json:"reference_type,omitempty"`
	ReferenceID     *string    `json:"reference_id,omitempty"`
	QuantityBefore  *float64   `json:"quantity_before,omitempty"`
	QuantityAfter   *float64   `json:"quantity_after,omitempty"`
	UnitCost        *float64   `json:"unit_cost,omitempty"`
	TotalCost       *float64   `json:"total_cost,omitempty"`
	CreatedBy       string     `json:"created_by"`
	ApprovedBy      *string    `json:"approved_by,omitempty"`
	Reason          *string    `json:"reason,omitempty"`
	Notes           *string    `json:"notes,omitempty"`
	IPAddress       *string    `json:"ip_address,omitempty"`
	UserAgent       *string    `json:"user_agent,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	
	// Joined fields
	Batch           *InventoryBatch `json:"batch,omitempty"`
	CreatedByEmployee *Employee      `json:"created_by_employee,omitempty"`
}

// CurrentInventoryView represents the pre-calculated current inventory view
type CurrentInventoryView struct {
	BatchID           string     `json:"batch_id"`
	PharmacyProductID string     `json:"pharmacy_product_id"`
	PharmacyID        string     `json:"pharmacy_id"`
	BranchID          string     `json:"branch_id"`
	GlobalProductID   string     `json:"global_product_id"`
	ProductName       string     `json:"product_name"`
	GenericName       *string    `json:"generic_name,omitempty"`
	BrandName         *string    `json:"brand_name,omitempty"`
	Barcode           *string    `json:"barcode,omitempty"`
	DosageForm        string     `json:"dosage_form"`
	Strength          *string    `json:"strength,omitempty"`
	BatchNumber       string     `json:"batch_number"`
	Unit              string     `json:"unit"`
	Quantity          float64    `json:"quantity"`
	CostPerUnit       float64    `json:"cost_per_unit"`
	TotalCost         float64    `json:"total_cost"`
	ExpiryDate        *time.Time `json:"expiry_date,omitempty"`
	DaysUntilExpiry   *int       `json:"days_until_expiry,omitempty"`
	SellingPrice      float64    `json:"selling_price"`
	MinStockLevel     float64    `json:"min_stock_level"`
	BranchName        *string    `json:"branch_name,omitempty"`
	Status            string     `json:"status"` // low_stock, expiring_soon, quarantined, normal
}

// ============================================
// Attendance Model (Updated)
// ============================================

// AttendanceRecord represents an employee attendance entry
type AttendanceRecord struct {
	ID              string     `json:"id"`
	EmployeeID      string     `json:"employee_id"`
	BranchID        string     `json:"branch_id"`
	PharmacyID      string     `json:"pharmacy_id"`
	ClockIn         time.Time  `json:"clock_in"`
	ClockOut        *time.Time `json:"clock_out,omitempty"`
	TotalMinutes    *int       `json:"total_minutes,omitempty"`
	Status          string     `json:"status"` // active, completed, adjusted, missed_clockout
	Notes           *string    `json:"notes,omitempty"`
	AdjustmentReason *string   `json:"adjustment_reason,omitempty"`
	AdjustedBy      *string    `json:"adjusted_by,omitempty"`
	AdjustedAt      *time.Time `json:"adjusted_at,omitempty"`
	ClockInIP       *string    `json:"clock_in_ip,omitempty"`
	ClockOutIP      *string    `json:"clock_out_ip,omitempty"`
	DeviceInfo      map[string]interface{} `json:"device_info,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
	
	// Joined fields
	Employee *Employee `json:"employee,omitempty"`
	Branch   *Branch   `json:"branch,omitempty"`
}

// ============================================
// Audit Log Model (Updated)
// ============================================

// AuditLog represents an audit trail entry
type AuditLog struct {
	ID               string     `json:"id"`
	PharmacyID       string     `json:"pharmacy_id"`
	AccountID        string     `json:"account_id"`
	ActorID          *string    `json:"actor_id,omitempty"`
	ActorEmail       *string    `json:"actor_email,omitempty"`
	ActorDisplayName *string    `json:"actor_display_name,omitempty"`
	ActorRole        *string    `json:"actor_role,omitempty"`
	ActorAuthUserID  *string    `json:"actor_auth_user_id,omitempty"`
	Action           string     `json:"action"`
	ActionCategory   *string    `json:"action_category,omitempty"`
	EntityType       string     `json:"entity_type"`
	EntityID         *string    `json:"entity_id,omitempty"`
	OldValues        map[string]interface{} `json:"old_values,omitempty"`
	NewValues        map[string]interface{} `json:"new_values,omitempty"`
	ChangesSummary   *string    `json:"changes_summary,omitempty"`
	FieldsChanged    []string   `json:"fields_changed,omitempty"`
	RequestID        *string    `json:"request_id,omitempty"`
	IPAddress        *string    `json:"ip_address,omitempty"`
	UserAgent        *string    `json:"user_agent,omitempty"`
	ClientInfo       map[string]interface{} `json:"client_info,omitempty"`
	Success          bool       `json:"success"`
	ErrorMessage     *string    `json:"error_message,omitempty"`
	DurationMs       *int       `json:"duration_ms,omitempty"`
	Severity         string     `json:"severity"` // info, warning, critical
	Tags             []string   `json:"tags,omitempty"`
	Notes            *string    `json:"notes,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
}

// ============================================
// Request/Response DTOs (Data Transfer Objects)
// ============================================

// CreateGlobalProductRequest represents request body for creating a global product
type CreateGlobalProductRequest struct {
	Name                 string   `json:"name" binding:"required"`
	GenericName          *string  `json:"generic_name,omitempty"`
	BrandName            *string  `json:"brand_name,omitempty"`
	DosageForm           string   `json:"dosage_form" binding:"required"`
	Strength             *string  `json:"strength,omitempty"`
	ProductCategory      string   `json:"product_category"`
	RequiresPrescription string   `json:"requires_prescription"`
	ControlledSubstance  bool     `json:"controlled_substance"`
	ScheduleCategory     *string  `json:"schedule_category,omitempty"`
	Barcode              *string  `json:"barcode,omitempty"`
	BarcodeType          *string  `json:"barcode_type,omitempty"`
	NationalCode         *string  `json:"national_code,omitempty"`
	ManufacturerSKU      *string  `json:"manufacturer_sku,omitempty"`
	ManufacturerName     *string  `json:"manufacturer_name,omitempty"`
	ManufacturerCountry  *string  `json:"manufacturer_country,omitempty"`
	ActiveIngredient      *string  `json:"active_ingredient,omitempty"`
	TherapeuticClass     *string  `json:"therapeutic_class,omitempty"`
	ATCCode              *string  `json:"atc_code,omitempty"`
	DefaultUnit          string   `json:"default_unit"`
	Description          *string  `json:"description,omitempty"`
	StorageInstructions  *string  `json:"storage_instructions,omitempty"`
}

// AddPharmacyProductRequest represents request body for adding product to pharmacy
type AddPharmacyProductRequest struct {
	GlobalProductID     string   `json:"global_product_id" binding:"required"`
	CostPrice           float64  `json:"cost_price"`
	SellingPrice        float64  `json:"selling_price" binding:"required"`
	MarginPercentage     *float64 `json:"margin_percentage,omitempty"`
	TaxRate              float64  `json:"tax_rate"`
	TaxCategory          *string  `json:"tax_category,omitempty"`
	MinStockLevel        float64  `json:"min_stock_level"`
	MaxStockLevel        *float64 `json:"max_stock_level,omitempty"`
	ReorderQuantity      *float64 `json:"reorder_quantity,omitempty"`
	InternalSKU          *string  `json:"internal_sku,omitempty"`
	ShelfLocation        *string  `json:"shelf_location,omitempty"`
	BinLocation          *string  `json:"bin_location,omitempty"`
}

// CreateInventoryBatchRequest represents request body for creating an inventory batch
type CreateInventoryBatchRequest struct {
	PharmacyProductID string  `json:"pharmacy_product_id" binding:"required"`
	BranchID          string  `json:"branch_id" binding:"required"`
	BatchNumber       string  `json:"batch_number" binding:"required"`
	Barcode           *string `json:"barcode,omitempty"`
	Quantity          float64 `json:"quantity" binding:"required,gt=0"`
	Unit              string  `json:"unit" binding:"required"`
	CostPerUnit       float64 `json:"cost_per_unit" binding:"required,gte=0"`
	ManufactureDate   *string `json:"manufacture_date,omitempty"` // ISO date format
	ExpiryDate        *string `json:"expiry_date,omitempty"`      // ISO date format
	SupplierName      *string `json:"supplier_name,omitempty"`
	SupplierReference *string `json:"supplier_reference,omitempty"`
	Location          *string `json:"location,omitempty"`
	ReferenceType     *string `json:"reference_type,omitempty"`
	ReferenceID       *string `json:"reference_id,omitempty"`
}

// CreateStockMovementRequest represents request body for creating a stock movement
type CreateStockMovementRequest struct {
	BatchID       string  `json:"batch_id" binding:"required"`
	MovementType  string  `json:"movement_type" binding:"required"`
	Quantity      float64 `json:"quantity" binding:"required"`
	Unit          string  `json:"unit" binding:"required"`
	ReferenceType *string `json:"reference_type,omitempty"`
	ReferenceID   *string `json:"reference_id,omitempty"`
	Reason        *string `json:"reason,omitempty"` // Required for adjustments
	Notes         *string `json:"notes,omitempty"`
}

// SearchProductsRequest represents query parameters for product search
type SearchProductsRequest struct {
	Query       string   `form:"query"`
	Category    string   `form:"category"`
	DosageForm  string   `form:"dosage_form"`
	Manufacturer string  `form:"manufacturer"`
	RequiresRx  *bool    `form:"requires_prescription"`
	Page        int      `form:"page" binding:"min=1"`
	PageSize    int      `form:"page_size" binding:"min=1,max=100"`
	SortBy      string   `form:"sort_by"` // name, generic_name, brand_name, created_at
	SortOrder   string   `form:"sort_order"` // asc, desc
}

// PaginatedResponse represents a paginated API response
type PaginatedResponse struct {
	Data       interface{} `json:"data"`
	Pagination Pagination  `json:"pagination"`
}

// Pagination contains pagination metadata
type Pagination struct {
	Page       int   `json:"page"`
	PageSize   int   `json:"page_size"`
	TotalItems int   `json:"total_items"`
	TotalPages int   `json:"total_pages"`
	HasNext    bool  `json:"has_next"`
	HasPrev    bool  `json:"has_prev"`
}
