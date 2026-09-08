// Package repository provides database access for Global Products
// This handles the shared product catalog (not tenant-specific)
package repository

import (
        "context"
        "fmt"
        "strings"

        "github.com/jackc/pgx/v5/pgxpool"

        "github.com/pharmacy-os/backend/internal/models"
)

// GlobalProductRepository handles database operations for global products
type GlobalProductRepository struct {
        pool *pgxpool.Pool
}

// NewGlobalProductRepository creates a new global product repository
func NewGlobalProductRepository(pool *pgxpool.Pool) *GlobalProductRepository {
        return &GlobalProductRepository{pool: pool}
}

// Create inserts a new global product into the catalog
func (r *GlobalProductRepository) Create(ctx context.Context, product *models.GlobalProduct) error {
        query := `
                INSERT INTO global_products (
                        name, generic_name, brand_name, dosage_form, strength,
                        product_category, requires_prescription, controlled_substance,
                        schedule_category, barcode, barcode_type, national_code,
                        manufacturer_sku, manufacturer_name, manufacturer_country,
                        active_ingredient, therapeutic_class, atc_code,
                        default_unit, description, storage_instructions,
                        is_active, created_by
                ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
                        $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23
                )
                RETURNING id, created_at, updated_at
        `

        err := r.pool.QueryRow(ctx, query,
                product.Name,
                product.GenericName,
                product.BrandName,
                product.DosageForm,
                product.Strength,
                product.ProductCategory,
                product.RequiresPrescription,
                product.ControlledSubstance,
                product.ScheduleCategory,
                product.Barcode,
                product.BarcodeType,
                product.NationalCode,
                product.ManufacturerSKU,
                product.ManufacturerName,
                product.ManufacturerCountry,
                product.ActiveIngredient,
                product.TherapeuticClass,
                product.ATCCode,
                product.DefaultUnit,
                product.Description,
                product.StorageInstructions,
                product.IsActive,
                product.CreatedBy,
        ).Scan(&product.ID, &product.CreatedAt, &product.UpdatedAt)

        if err != nil {
                return fmt.Errorf("failed to create global product: %w", err)
        }

        return nil
}

// GetByID retrieves a global product by its ID
func (r *GlobalProductRepository) GetByID(ctx context.Context, id string) (*models.GlobalProduct, error) {
        query := `
                SELECT 
                        id, name, generic_name, brand_name, dosage_form, strength,
                        product_category, requires_prescription, controlled_substance,
                        schedule_category, barcode, barcode_type, national_code,
                        manufacturer_sku, manufacturer_name, manufacturer_country,
                        active_ingredient, therapeutic_class, atc_code,
                        default_unit, description, storage_instructions,
                        is_active, created_by, created_at, updated_at
                FROM global_products
                WHERE id = $1
        `

        product := &models.GlobalProduct{}
        err := r.pool.QueryRow(ctx, query, id).Scan(
                &product.ID,
                &product.Name,
                &product.GenericName,
                &product.BrandName,
                &product.DosageForm,
                &product.Strength,
                &product.ProductCategory,
                &product.RequiresPrescription,
                &product.ControlledSubstance,
                &product.ScheduleCategory,
                &product.Barcode,
                &product.BarcodeType,
                &product.NationalCode,
                &product.ManufacturerSKU,
                &product.ManufacturerName,
                &product.ManufacturerCountry,
                &product.ActiveIngredient,
                &product.TherapeuticClass,
                &product.ATCCode,
                &product.DefaultUnit,
                &product.Description,
                &product.StorageInstructions,
                &product.IsActive,
                &product.CreatedBy,
                &product.CreatedAt,
                &product.UpdatedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get global product by ID %s: %w", id, err)
        }

        return product, nil
}

// GetByBarcode retrieves a global product by barcode
func (r *GlobalProductRepository) GetByBarcode(ctx context.Context, barcode string) (*models.GlobalProduct, error) {
        query := `
                SELECT 
                        id, name, generic_name, brand_name, dosage_form, strength,
                        product_category, requires_prescription, controlled_substance,
                        schedule_category, barcode, barcode_type, national_code,
                        manufacturer_sku, manufacturer_name, manufacturer_country,
                        active_ingredient, therapeutic_class, atc_code,
                        default_unit, description, storage_instructions,
                        is_active, created_by, created_at, updated_at
                FROM global_products
                WHERE barcode = $1 AND is_active = true
        `

        product := &models.GlobalProduct{}
        err := r.pool.QueryRow(ctx, query, barcode).Scan(
                &product.ID,
                &product.Name,
                &product.GenericName,
                &product.BrandName,
                &product.DosageForm,
                &product.Strength,
                &product.ProductCategory,
                &product.RequiresPrescription,
                &product.ControlledSubstance,
                &product.ScheduleCategory,
                &product.Barcode,
                &product.BarcodeType,
                &product.NationalCode,
                &product.ManufacturerSKU,
                &product.ManufacturerName,
                &product.ManufacturerCountry,
                &product.ActiveIngredient,
                &product.TherapeuticClass,
                &product.ATCCode,
                &product.DefaultUnit,
                &product.Description,
                &product.StorageInstructions,
                &product.IsActive,
                &product.CreatedBy,
                &product.CreatedAt,
                &product.UpdatedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get global product by barcode %s: %w", barcode, err)
        }

        return product, nil
}

// Search searches for products in the global catalog with pagination and filtering
func (r *GlobalProductRepository) Search(ctx context.Context, req *models.SearchProductsRequest) (*models.PaginatedResponse, error) {
        // Set defaults
        if req.Page == 0 {
                req.Page = 1
        }
        if req.PageSize == 0 {
                req.PageSize = 20
        }
        if req.SortBy == "" {
                req.SortBy = "name"
        }
        if req.SortOrder == "" {
                req.SortOrder = "asc"
        }

        // Build WHERE clause dynamically
        conditions := []string{"is_active = true"}
        args := []interface{}{}
        argNum := 1

        if req.Query != "" {
                conditions = append(conditions, fmt.Sprintf(
                        "(to_tsvector('english', COALESCE(name, '') || ' ' || COALESCE(generic_name, '') || ' ' || COALESCE(brand_name, '')) @@ plainto_tsquery($%d))",
                        argNum,
                ))
                args = append(args, req.Query)
                argNum++
        }

        if req.Category != "" {
                conditions = append(conditions, fmt.Sprintf("product_category = $%d", argNum))
                args = append(args, req.Category)
                argNum++
        }

        if req.DosageForm != "" {
                conditions = append(conditions, fmt.Sprintf("dosage_form = $%d", argNum))
                args = append(args, req.DosageForm)
                argNum++
        }

        if req.Manufacturer != "" {
                conditions = append(conditions, fmt.Sprintf("manufacturer_name ILIKE $%d", argNum))
                args = append(args, "%"+req.Manufacturer+"%")
                argNum++
        }

        if req.RequiresRx != nil {
                conditions = append(conditions, fmt.Sprintf("requires_prescription = $%d", argNum))
                if *req.RequiresRx {
                        args = append(args, "yes")
                } else {
                        args = append(args, "no")
                }
                argNum++
        }

        whereClause := strings.Join(conditions, " AND ")

        // Validate sort column to prevent SQL injection
        validSortColumns := map[string]bool{
                "name": true, "generic_name": true, "brand_name": true,
                "created_at": true, "dosage_form": true, "manufacturer_name": true,
        }
        if !validSortColumns[req.SortBy] {
                req.SortBy = "name"
        }

        // Validate sort order
        if req.SortOrder != "asc" && req.SortOrder != "desc" {
                req.SortOrder = "asc"
        }

        // Get total count
        countQuery := fmt.Sprintf("SELECT COUNT(*) FROM global_products WHERE %s", whereClause)
        var totalItems int
        err := r.pool.QueryRow(ctx, countQuery, args...).Scan(&totalItems)
        if err != nil {
                return nil, fmt.Errorf("failed to count global products: %w", err)
        }

        // Calculate pagination
        offset := (req.Page - 1) * req.PageSize
        totalPages := (totalItems + req.PageSize - 1) / req.PageSize

        // Build SELECT query
        selectQuery := fmt.Sprintf(`
                SELECT 
                        id, name, generic_name, brand_name, dosage_form, strength,
                        product_category, requires_prescription, controlled_substance,
                        barcode, default_unit, manufacturer_name, is_active, created_at
                FROM global_products
                WHERE %s
                ORDER BY %s %s
                LIMIT $%d OFFSET $%d
        `, whereClause, req.SortBy, req.SortOrder, argNum, argNum+1)

        args = append(args, req.PageSize, offset)

        rows, err := r.pool.Query(ctx, selectQuery, args...)
        if err != nil {
                return nil, fmt.Errorf("failed to search global products: %w", err)
        }
        defer rows.Close()

        products := make([]*models.GlobalProduct, 0)
        for rows.Next() {
                product := &models.GlobalProduct{}
                err := rows.Scan(
                        &product.ID,
                        &product.Name,
                        &product.GenericName,
                        &product.BrandName,
                        &product.DosageForm,
                        &product.Strength,
                        &product.ProductCategory,
                        &product.RequiresPrescription,
                        &product.ControlledSubstance,
                        &product.Barcode,
                        &product.DefaultUnit,
                        &product.ManufacturerName,
                        &product.IsActive,
                        &product.CreatedAt,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan global product row: %w", err)
                }
                products = append(products, product)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating global products: %w", err)
        }

        response := &models.PaginatedResponse{
                Data: products,
                Pagination: models.Pagination{
                        Page:       req.Page,
                        PageSize:   req.PageSize,
                        TotalItems: totalItems,
                        TotalPages: totalPages,
                        HasNext:    req.Page < totalPages,
                        HasPrev:    req.Page > 1,
                },
        }

        return response, nil
}

// Update updates an existing global product
func (r *GlobalProductRepository) Update(ctx context.Context, product *models.GlobalProduct) error {
        query := `
                UPDATE global_products SET
                        name = $2,
                        generic_name = $3,
                        brand_name = $4,
                        dosage_form = $5,
                        strength = $6,
                        product_category = $7,
                        requires_prescription = $8,
                        controlled_substance = $9,
                        schedule_category = $10,
                        barcode = $11,
                        barcode_type = $12,
                        national_code = $13,
                        manufacturer_sku = $14,
                        manufacturer_name = $15,
                        manufacturer_country = $16,
                        active_ingredient = $17,
                        therapeutic_class = $18,
                        atc_code = $19,
                        default_unit = $20,
                        description = $21,
                        storage_instructions = $22,
                        is_active = $23,
                        updated_at = NOW()
                WHERE id = $1
                RETURNING updated_at
        `

        err := r.pool.QueryRow(ctx, query,
                product.ID,
                product.Name,
                product.GenericName,
                product.BrandName,
                product.DosageForm,
                product.Strength,
                product.ProductCategory,
                product.RequiresPrescription,
                product.ControlledSubstance,
                product.ScheduleCategory,
                product.Barcode,
                product.BarcodeType,
                product.NationalCode,
                product.ManufacturerSKU,
                product.ManufacturerName,
                product.ManufacturerCountry,
                product.ActiveIngredient,
                product.TherapeuticClass,
                product.ATCCode,
                product.DefaultUnit,
                product.Description,
                product.StorageInstructions,
                product.IsActive,
        ).Scan(&product.UpdatedAt)

        if err != nil {
                return fmt.Errorf("failed to update global product: %w", err)
        }

        return nil
}

// Delete soft-deletes a global product (sets is_active = false)
func (r *GlobalProductRepository) Delete(ctx context.Context, id string) error {
        query := `UPDATE global_products SET is_active = false, updated_at = NOW() WHERE id = $1`
        
        result, err := r.pool.Exec(ctx, query, id)
        if err != nil {
                return fmt.Errorf("failed to delete global product: %w", err)
        }

        if result.RowsAffected() == 0 {
                return fmt.Errorf("global product not found: %s", id)
        }

        return nil
}

// ListAllActive returns all active global products (use with caution - for admin only)
func (r *GlobalProductRepository) ListAllActive(ctx context.Context) ([]*models.GlobalProduct, error) {
        query := `
                SELECT 
                        id, name, generic_name, brand_name, dosage_form, strength,
                        barcode, default_unit, manufacturer_name, is_active, created_at
                FROM global_products
                WHERE is_active = true
                ORDER BY name ASC
                LIMIT 1000
        `

        rows, err := r.pool.Query(ctx, query)
        if err != nil {
                return nil, fmt.Errorf("failed to list active global products: %w", err)
        }
        defer rows.Close()

        products := make([]*models.GlobalProduct, 0)
        for rows.Next() {
                product := &models.GlobalProduct{}
                err := rows.Scan(
                        &product.ID,
                        &product.Name,
                        &product.GenericName,
                        &product.BrandName,
                        &product.DosageForm,
                        &product.Strength,
                        &product.Barcode,
                        &product.DefaultUnit,
                        &product.ManufacturerName,
                        &product.IsActive,
                        &product.CreatedAt,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan global product row: %w", err)
                }
                products = append(products, product)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating global products: %w", err)
        }

        return products, nil
}

// CheckBarcodeExists checks if a barcode already exists for a different product
func (r *GlobalProductRepository) CheckBarcodeExists(ctx context.Context, barcode string, excludeID string) (bool, error) {
        query := `SELECT EXISTS(SELECT 1 FROM global_products WHERE barcode = $1 AND id != $2 AND is_active = true)`
        
        var exists bool
        err := r.pool.QueryRow(ctx, query, barcode, excludeID).Scan(&exists)
        if err != nil {
                return false, fmt.Errorf("failed to check barcode existence: %w", err)
        }
        
        return exists, nil
}
