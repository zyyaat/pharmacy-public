// Package repository provides database access for Pharmacy Products
// This handles tenant-specific product data (pricing, stock levels, etc.)
package repository

import (
        "context"
        "fmt"
        "strings"

        "github.com/jackc/pgx/v5/pgxpool"

        "github.com/pharmacy-os/backend/internal/models"
)

// PharmacyProductRepository handles database operations for pharmacy-specific products
type PharmacyProductRepository struct {
        pool *pgxpool.Pool
}

// NewPharmacyProductRepository creates a new pharmacy product repository
func NewPharmacyProductRepository(pool *pgxpool.Pool) *PharmacyProductRepository {
        return &PharmacyProductRepository{pool: pool}
}

// Add adds a new product to a pharmacy's catalog (from global catalog)
func (r *PharmacyProductRepository) Add(ctx context.Context, product *models.PharmacyProduct) error {
        query := `
                INSERT INTO pharmacy_products (
                        pharmacy_id, global_product_id,
                        cost_price, selling_price, margin_percentage,
                        tax_rate, tax_category,
                        min_stock_level, max_stock_level, reorder_quantity,
                        preferred_supplier_id,
                        internal_sku, shelf_location, bin_location,
                        is_active, is_discontinued
                ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16
                )
                RETURNING id, first_added_at, created_at, updated_at
        `

        err := r.pool.QueryRow(ctx, query,
                product.PharmacyID,
                product.GlobalProductID,
                product.CostPrice,
                product.SellingPrice,
                product.MarginPercentage,
                product.TaxRate,
                product.TaxCategory,
                product.MinStockLevel,
                product.MaxStockLevel,
                product.ReorderQuantity,
                product.PreferredSupplierID,
                product.InternalSKU,
                product.ShelfLocation,
                product.BinLocation,
                product.IsActive,
                product.IsDiscontinued,
        ).Scan(&product.ID, &product.FirstAddedAt, &product.CreatedAt, &product.UpdatedAt)

        if err != nil {
                return fmt.Errorf("failed to add pharmacy product: %w", err)
        }

        return nil
}

// GetByID retrieves a pharmacy product by its ID
func (r *PharmacyProductRepository) GetByID(ctx context.Context, id string) (*models.PharmacyProduct, error) {
        query := `
                SELECT 
                        pp.id, pp.pharmacy_id, pp.global_product_id,
                        pp.cost_price, pp.selling_price, pp.margin_percentage,
                        pp.tax_rate, pp.tax_category,
                        pp.min_stock_level, pp.max_stock_level, pp.reorder_quantity,
                        pp.preferred_supplier_id,
                        pp.internal_sku, pp.shelf_location, pp.bin_location,
                        pp.is_active, pp.is_discontinued,
                        pp.first_added_at, pp.last_received_at, pp.last_sold_at,
                        pp.created_at, pp.updated_at,
                        gp.id, gp.name, gp.generic_name, gp.brand_name,
                        gp.dosage_form, gp.strength, gp.barcode, gp.default_unit,
                        gp.manufacturer_name, gp.requires_prescription
                FROM pharmacy_products pp
                JOIN global_products gp ON pp.global_product_id = gp.id
                WHERE pp.id = $1
        `

        product := &models.PharmacyProduct{
                GlobalProduct: &models.GlobalProduct{},
        }
        
        err := r.pool.QueryRow(ctx, query, id).Scan(
                &product.ID,
                &product.PharmacyID,
                &product.GlobalProductID,
                &product.CostPrice,
                &product.SellingPrice,
                &product.MarginPercentage,
                &product.TaxRate,
                &product.TaxCategory,
                &product.MinStockLevel,
                &product.MaxStockLevel,
                &product.ReorderQuantity,
                &product.PreferredSupplierID,
                &product.InternalSKU,
                &product.ShelfLocation,
                &product.BinLocation,
                &product.IsActive,
                &product.IsDiscontinued,
                &product.FirstAddedAt,
                &product.LastReceivedAt,
                &product.LastSoldAt,
                &product.CreatedAt,
                &product.UpdatedAt,
                // Global product fields
                &product.GlobalProduct.ID,
                &product.GlobalProduct.Name,
                &product.GlobalProduct.GenericName,
                &product.GlobalProduct.BrandName,
                &product.GlobalProduct.DosageForm,
                &product.GlobalProduct.Strength,
                &product.GlobalProduct.Barcode,
                &product.GlobalProduct.DefaultUnit,
                &product.GlobalProduct.ManufacturerName,
                &product.GlobalProduct.RequiresPrescription,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get pharmacy product by ID %s: %w", id, err)
        }

        return product, nil
}

// GetByPharmacyAndGlobalProduct retrieves a pharmacy product by pharmacy and global product IDs
func (r *PharmacyProductRepository) GetByPharmacyAndGlobalProduct(
        ctx context.Context, 
        pharmacyID string, 
        globalProductID string,
) (*models.PharmacyProduct, error) {
        query := `
                SELECT 
                        id, pharmacy_id, global_product_id,
                        cost_price, selling_price, margin_percentage,
                        tax_rate, tax_category,
                        min_stock_level, max_stock_level, reorder_quantity,
                        preferred_supplier_id,
                        internal_sku, shelf_location, bin_location,
                        is_active, is_discontinued,
                        first_added_at, last_received_at, last_sold_at,
                        created_at, updated_at
                FROM pharmacy_products
                WHERE pharmacy_id = $1 AND global_product_id = $2
        `

        product := &models.PharmacyProduct{}
        err := r.pool.QueryRow(ctx, query, pharmacyID, globalProductID).Scan(
                &product.ID,
                &product.PharmacyID,
                &product.GlobalProductID,
                &product.CostPrice,
                &product.SellingPrice,
                &product.MarginPercentage,
                &product.TaxRate,
                &product.TaxCategory,
                &product.MinStockLevel,
                &product.MaxStockLevel,
                &product.ReorderQuantity,
                &product.PreferredSupplierID,
                &product.InternalSKU,
                &product.ShelfLocation,
                &product.BinLocation,
                &product.IsActive,
                &product.IsDiscontinued,
                &product.FirstAddedAt,
                &product.LastReceivedAt,
                &product.LastSoldAt,
                &product.CreatedAt,
                &product.UpdatedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get pharmacy product: %w", err)
        }

        return product, nil
}

// ListByPharmacy lists all products for a pharmacy with pagination and filtering
func (r *PharmacyProductRepository) ListByPharmacy(
        ctx context.Context,
        pharmacyID string,
        page, pageSize int,
        searchQuery string,
        activeOnly bool,
) (*models.PaginatedResponse, error) {
        // Set defaults
        if page == 0 {
                page = 1
        }
        if pageSize == 0 {
                pageSize = 20
        }

        // Build WHERE clause
        conditions := []string{"pp.pharmacy_id = $1"}
        args := []interface{}{pharmacyID}
        argNum := 2

        if searchQuery != "" {
                conditions = append(conditions, fmt.Sprintf(
                        "(gp.name ILIKE $%d OR gp.generic_name ILIKE $%d OR pp.internal_sku ILIKE $%d)",
                        argNum, argNum, argNum+1,
                ))
                args = append(args, "%"+searchQuery+"%", "%"+searchQuery+"%", "%"+searchQuery+"%")
                argNum += 3
        }

        if activeOnly {
                conditions = append(conditions, "pp.is_active = true AND gp.is_active = true")
        }

        whereClause := strings.Join(conditions, " AND ")

        // Get total count
        countQuery := fmt.Sprintf(`
                SELECT COUNT(*) FROM pharmacy_products pp
                JOIN global_products gp ON pp.global_product_id = gp.id
                WHERE %s
        `, whereClause)

        var totalItems int
        err := r.pool.QueryRow(ctx, countQuery, args...).Scan(&totalItems)
        if err != nil {
                return nil, fmt.Errorf("failed to count pharmacy products: %w", err)
        }

        // Calculate pagination
        offset := (page - 1) * pageSize
        totalPages := (totalItems + pageSize - 1) / pageSize

        // Get data
        selectQuery := fmt.Sprintf(`
                SELECT 
                        pp.id, pp.pharmacy_id, pp.global_product_id,
                        pp.cost_price, pp.selling_price, pp.margin_percentage,
                        pp.min_stock_level, pp.is_active, pp.is_discontinued,
                        gp.name, gp.generic_name, gp.brand_name, gp.barcode,
                        gp.dosage_form, gp.strength, gp.default_unit
                FROM pharmacy_products pp
                JOIN global_products gp ON pp.global_product_id = gp.id
                WHERE %s
                ORDER BY gp.name ASC
                LIMIT $%d OFFSET $%d
        `, whereClause, argNum, argNum+1)

        args = append(args, pageSize, offset)

        rows, err := r.pool.Query(ctx, selectQuery, args...)
        if err != nil {
                return nil, fmt.Errorf("failed to list pharmacy products: %w", err)
        }
        defer rows.Close()

        products := make([]*models.PharmacyProduct, 0)
        for rows.Next() {
                product := &models.PharmacyProduct{
                        GlobalProduct: &models.GlobalProduct{},
                }
                
                err := rows.Scan(
                        &product.ID,
                        &product.PharmacyID,
                        &product.GlobalProductID,
                        &product.CostPrice,
                        &product.SellingPrice,
                        &product.MarginPercentage,
                        &product.MinStockLevel,
                        &product.IsActive,
                        &product.IsDiscontinued,
                        &product.GlobalProduct.Name,
                        &product.GlobalProduct.GenericName,
                        &product.GlobalProduct.BrandName,
                        &product.GlobalProduct.Barcode,
                        &product.GlobalProduct.DosageForm,
                        &product.GlobalProduct.Strength,
                        &product.GlobalProduct.DefaultUnit,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan pharmacy product row: %w", err)
                }
                products = append(products, product)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating pharmacy products: %w", err)
        }

        response := &models.PaginatedResponse{
                Data: products,
                Pagination: models.Pagination{
                        Page:       page,
                        PageSize:   pageSize,
                        TotalItems: totalItems,
                        TotalPages: totalPages,
                        HasNext:    page < totalPages,
                        HasPrev:    page > 1,
                },
        }

        return response, nil
}

// Update updates a pharmacy product's data
func (r *PharmacyProductRepository) Update(ctx context.Context, product *models.PharmacyProduct) error {
        query := `
                UPDATE pharmacy_products SET
                        cost_price = $2,
                        selling_price = $3,
                        margin_percentage = $4,
                        tax_rate = $5,
                        tax_category = $6,
                        min_stock_level = $7,
                        max_stock_level = $8,
                        reorder_quantity = $9,
                        preferred_supplier_id = $10,
                        internal_sku = $11,
                        shelf_location = $12,
                        bin_location = $13,
                        is_active = $14,
                        is_discontinued = $15,
                        updated_at = NOW()
                WHERE id = $1
                RETURNING updated_at
        `

        err := r.pool.QueryRow(ctx, query,
                product.ID,
                product.CostPrice,
                product.SellingPrice,
                product.MarginPercentage,
                product.TaxRate,
                product.TaxCategory,
                product.MinStockLevel,
                product.MaxStockLevel,
                product.ReorderQuantity,
                product.PreferredSupplierID,
                product.InternalSKU,
                product.ShelfLocation,
                product.BinLocation,
                product.IsActive,
                product.IsDiscontinued,
        ).Scan(&product.UpdatedAt)

        if err != nil {
                return fmt.Errorf("failed to update pharmacy product: %w", err)
        }

        return nil
}

// ToggleActive toggles the active status of a pharmacy product
func (r *PharmacyProductRepository) ToggleActive(ctx context.Context, id string) (*models.PharmacyProduct, error) {
        query := `
                UPDATE pharmacy_products SET
                        is_active = NOT is_active,
                        updated_at = NOW()
                WHERE id = $1
                RETURNING id, is_active, updated_at
        `

        product := &models.PharmacyProduct{}
        err := r.pool.QueryRow(ctx, query, id).Scan(
                &product.ID,
                &product.IsActive,
                &product.UpdatedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to toggle pharmacy product active status: %w", err)
        }

        return product, nil
}

// UpdateLastReceivedAt updates the last_received_at timestamp
func (r *PharmacyProductRepository) UpdateLastReceivedAt(ctx context.Context, id string) error {
        query := `UPDATE pharmacy_products SET last_received_at = NOW(), updated_at = NOW() WHERE id = $1`
        
        _, err := r.pool.Exec(ctx, query, id)
        if err != nil {
                return fmt.Errorf("failed to update last received at: %w", err)
        }
        
        return nil
}

// UpdateLastSoldAt updates the last_sold_at timestamp
func (r *PharmacyProductRepository) UpdateLastSoldAt(ctx context.Context, id string) error {
        query := `UPDATE pharmacy_products SET last_sold_at = NOW(), updated_at = NOW() WHERE id = $1`
        
        _, err := r.pool.Exec(ctx, query, id)
        if err != nil {
                return fmt.Errorf("failed to update last sold at: %w", err)
        }
        
        return nil
}

// ListLowStock returns products that are below their minimum stock level
func (r *PharmacyProductRepository) ListLowStock(ctx context.Context, pharmacyID string) ([]*models.PharmacyProduct, error) {
        query := `
                SELECT 
                        pp.id, pp.pharmacy_id, pp.global_product_id,
                        pp.cost_price, pp.selling_price, pp.min_stock_level,
                        gp.name, gp.generic_name, gp.barcode, gp.default_unit,
                        COALESCE(SUM(ib.quantity), 0) as current_quantity
                FROM pharmacy_products pp
                JOIN global_products gp ON pp.global_product_id = gp.id
                LEFT JOIN inventory_batches ib ON ib.pharmacy_product_id = pp.id
                WHERE pp.pharmacy_id = $1 
                  AND pp.is_active = true 
                  AND pp.min_stock_level > 0
                GROUP BY pp.id, gp.name, gp.generic_name, gp.barcode, gp.default_unit
                HAVING COALESCE(SUM(ib.quantity), 0) <= pp.min_stock_level
                ORDER BY gp.name ASC
        `

        rows, err := r.pool.Query(ctx, query, pharmacyID)
        if err != nil {
                return nil, fmt.Errorf("failed to list low stock products: %w", err)
        }
        defer rows.Close()

        products := make([]*models.PharmacyProduct, 0)
        for rows.Next() {
                product := &models.PharmacyProduct{
                        GlobalProduct: &models.GlobalProduct{},
                }
                var currentQuantity float64
                
                err := rows.Scan(
                        &product.ID,
                        &product.PharmacyID,
                        &product.GlobalProductID,
                        &product.CostPrice,
                        &product.SellingPrice,
                        &product.MinStockLevel,
                        &product.GlobalProduct.Name,
                        &product.GlobalProduct.GenericName,
                        &product.GlobalProduct.Barcode,
                        &product.GlobalProduct.DefaultUnit,
                        &currentQuantity,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan low stock product: %w", err)
                }
                products = append(products, product)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating low stock products: %w", err)
        }

        return products, nil
}

// CheckSKUExists checks if an internal SKU already exists for a pharmacy
func (r *PharmacyProductRepository) CheckSKUExists(ctx context.Context, pharmacyID, sku string, excludeID string) (bool, error) {
        query := `
                SELECT EXISTS(
                        SELECT 1 FROM pharmacy_products 
                        WHERE pharmacy_id = $1 AND internal_sku = $2 AND id != $3
                )
        `
        
        var exists bool
        err := r.pool.QueryRow(ctx, query, pharmacyID, sku, excludeID).Scan(&exists)
        if err != nil {
                return false, fmt.Errorf("failed to check SKU existence: %w", err)
        }
        
        return exists, nil
}
