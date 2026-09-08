// Package repository provides database access for Inventory Batches
// This handles physical inventory batches with expiry and cost tracking
package repository

import (
        "context"
        "fmt"
        "strings"

        "github.com/jackc/pgx/v5/pgxpool"

        "github.com/pharmacy-os/backend/internal/models"
)

// InventoryBatchRepository handles database operations for inventory batches
type InventoryBatchRepository struct {
        pool *pgxpool.Pool
}

// NewInventoryBatchRepository creates a new inventory batch repository
func NewInventoryBatchRepository(pool *pgxpool.Pool) *InventoryBatchRepository {
        return &InventoryBatchRepository{pool: pool}
}

// Create creates a new inventory batch (e.g., when receiving goods)
func (r *InventoryBatchRepository) Create(ctx context.Context, batch *models.InventoryBatch) error {
        query := `
                INSERT INTO inventory_batches (
                        pharmacy_product_id, branch_id,
                        batch_number, barcode,
                        quantity, unit,
                        cost_per_unit, total_cost,
                        manufacture_date, expiry_date,
                        supplier_name, supplier_reference,
                        location,
                        is_reserved, is_quarantined, quarantine_reason,
                        received_date, received_by,
                        reference_type, reference_id
                ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                        $11, $12, $13, $14, $15, $16, $17, $18, $19, $20
                )
                RETURNING id, days_until_expiry, created_at, updated_at
        `

        err := r.pool.QueryRow(ctx, query,
                batch.PharmacyProductID,
                batch.BranchID,
                batch.BatchNumber,
                batch.Barcode,
                batch.Quantity,
                batch.Unit,
                batch.CostPerUnit,
                // total_cost is generated automatically
                batch.ManufactureDate,
                batch.ExpiryDate,
                batch.SupplierName,
                batch.SupplierReference,
                batch.Location,
                batch.IsReserved,
                batch.IsQuarantined,
                batch.QuarantineReason,
                batch.ReceivedDate,
                batch.ReceivedBy,
                batch.ReferenceType,
                batch.ReferenceID,
        ).Scan(&batch.ID, &batch.DaysUntilExpiry, &batch.CreatedAt, &batch.UpdatedAt)

        if err != nil {
                return fmt.Errorf("failed to create inventory batch: %w", err)
        }

        return nil
}

// GetByID retrieves an inventory batch by ID with joined data
func (r *InventoryBatchRepository) GetByID(ctx context.Context, id string) (*models.InventoryBatch, error) {
        query := `
                SELECT 
                        ib.id, ib.pharmacy_product_id, ib.branch_id,
                        ib.batch_number, ib.barcode,
                        ib.quantity, ib.unit,
                        ib.cost_per_unit, ib.total_cost,
                        ib.manufacture_date, ib.expiry_date, ib.days_until_expiry,
                        ib.supplier_name, ib.supplier_reference,
                        ib.location,
                        ib.is_reserved, ib.is_quarantined, ib.quarantine_reason,
                        ib.received_date, ib.received_by,
                        ib.reference_type, ib.reference_id,
                        ib.created_at, ib.updated_at,
                        gp.name as product_name, gp.generic_name, gp.barcode as product_barcode,
                        b.name as branch_name
                FROM inventory_batches ib
                JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
                JOIN global_products gp ON pp.global_product_id = gp.id
                LEFT JOIN branches b ON ib.branch_id = b.id
                WHERE ib.id = $1
        `

        batch := &models.InventoryBatch{
                PharmacyProduct: &models.PharmacyProduct{},
                GlobalProduct:   &models.GlobalProduct{},
                Branch:          &models.Branch{},
        }
        
        err := r.pool.QueryRow(ctx, query, id).Scan(
                &batch.ID,
                &batch.PharmacyProductID,
                &batch.BranchID,
                &batch.BatchNumber,
                &batch.Barcode,
                &batch.Quantity,
                &batch.Unit,
                &batch.CostPerUnit,
                &batch.TotalCost,
                &batch.ManufactureDate,
                &batch.ExpiryDate,
                &batch.DaysUntilExpiry,
                &batch.SupplierName,
                &batch.SupplierReference,
                &batch.Location,
                &batch.IsReserved,
                &batch.IsQuarantined,
                &batch.QuarantineReason,
                &batch.ReceivedDate,
                &batch.ReceivedBy,
                &batch.ReferenceType,
                &batch.ReferenceID,
                &batch.CreatedAt,
                &batch.UpdatedAt,
                &batch.GlobalProduct.Name,
                &batch.GlobalProduct.GenericName,
                &batch.GlobalProduct.Barcode,
                &batch.Branch.Name,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get inventory batch by ID %s: %w", id, err)
        }

        return batch, nil
}

// ListByPharmacyProduct lists all batches for a specific pharmacy product
func (r *InventoryBatchRepository) ListByPharmacyProduct(
        ctx context.Context,
        pharmacyProductID string,
        includeEmpty bool,
) ([]*models.InventoryBatch, error) {
        query := `
                SELECT 
                        id, pharmacy_product_id, branch_id,
                        batch_number, quantity, unit,
                        cost_per_unit, total_cost,
                        expiry_date, days_until_expiry,
                        is_reserved, is_quarantined,
                        received_date, created_at
                FROM inventory_batches
                WHERE pharmacy_product_id = $1
                ORDER BY 
                        CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END,
                        expiry_date ASC,
                        received_date DESC
        `

        if !includeEmpty {
                query += " AND quantity > 0"
        }

        rows, err := r.pool.Query(ctx, query, pharmacyProductID)
        if err != nil {
                return nil, fmt.Errorf("failed to list batches for product %s: %w", pharmacyProductID, err)
        }
        defer rows.Close()

        batches := make([]*models.InventoryBatch, 0)
        for rows.Next() {
                batch := &models.InventoryBatch{}
                err := rows.Scan(
                        &batch.ID,
                        &batch.PharmacyProductID,
                        &batch.BranchID,
                        &batch.BatchNumber,
                        &batch.Quantity,
                        &batch.Unit,
                        &batch.CostPerUnit,
                        &batch.TotalCost,
                        &batch.ExpiryDate,
                        &batch.DaysUntilExpiry,
                        &batch.IsReserved,
                        &batch.IsQuarantined,
                        &batch.ReceivedDate,
                        &batch.CreatedAt,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan inventory batch: %w", err)
                }
                batches = append(batches, batch)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating inventory batches: %w", err)
        }

        return batches, nil
}

// ListByBranch lists all batches for a branch with optional filtering
func (r *InventoryBatchRepository) ListByBranch(
        ctx context.Context,
        branchID string,
        lowStockOnly bool,
        expiringSoon bool,
        page, pageSize int,
) (*models.PaginatedResponse, error) {
        // Set defaults
        if page == 0 {
                page = 1
        }
        if pageSize == 0 {
                pageSize = 20
        }

        // Build conditions
        conditions := []string{"ib.branch_id = $1"}
        args := []interface{}{branchID}
        argNum := 2

        if lowStockOnly {
                conditions = append(conditions, "ib.quantity <= pp.min_stock_level")
        }

        if expiringSoon {
                conditions = append(conditions, "ib.days_until_expiry IS NOT NULL AND ib.days_until_expiry <= 90")
        }

        whereClause := strings.Join(conditions, " AND ")

        // Count query
        countQuery := fmt.Sprintf(`
                SELECT COUNT(*) FROM inventory_batches ib
                JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
                WHERE %s
        `, whereClause)

        var totalItems int
        err := r.pool.QueryRow(ctx, countQuery, args...).Scan(&totalItems)
        if err != nil {
                return nil, fmt.Errorf("failed to count inventory batches: %w", err)
        }

        // Data query
        offset := (page - 1) * pageSize
        totalPages := (totalItems + pageSize - 1) / pageSize

        selectQuery := fmt.Sprintf(`
                SELECT 
                        ib.id, ib.pharmacy_product_id, ib.branch_id,
                        ib.batch_number, ib.quantity, ib.unit,
                        ib.cost_per_unit, ib.total_cost,
                        ib.expiry_date, ib.days_until_expiry,
                        ib.is_quarantined,
                        gp.name as product_name, gp.generic_name, gp.barcode,
                        pp.selling_price, pp.min_stock_level
                FROM inventory_batches ib
                JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
                JOIN global_products gp ON pp.global_product_id = gp.id
                WHERE %s
                ORDER BY gp.name ASC, ib.expiry_date ASC
                LIMIT $%d OFFSET $%d
        `, whereClause, argNum, argNum+1)

        args = append(args, pageSize, offset)

        rows, err := r.pool.Query(ctx, selectQuery, args...)
        if err != nil {
                return nil, fmt.Errorf("failed to list inventory batches: %w", err)
        }
        defer rows.Close()

        batches := make([]*models.InventoryBatch, 0)
        for rows.Next() {
                batch := &models.InventoryBatch{
                        GlobalProduct:   &models.GlobalProduct{},
                        PharmacyProduct: &models.PharmacyProduct{},
                }
                
                err := rows.Scan(
                        &batch.ID,
                        &batch.PharmacyProductID,
                        &batch.BranchID,
                        &batch.BatchNumber,
                        &batch.Quantity,
                        &batch.Unit,
                        &batch.CostPerUnit,
                        &batch.TotalCost,
                        &batch.ExpiryDate,
                        &batch.DaysUntilExpiry,
                        &batch.IsQuarantined,
                        &batch.GlobalProduct.Name,
                        &batch.GlobalProduct.GenericName,
                        &batch.GlobalProduct.Barcode,
                        &batch.PharmacyProduct.SellingPrice,
                        &batch.PharmacyProduct.MinStockLevel,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan inventory batch row: %w", err)
                }
                batches = append(batches, batch)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating inventory batches: %w", err)
        }

        response := &models.PaginatedResponse{
                Data: batches,
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

// Update updates an inventory batch
func (r *InventoryBatchRepository) Update(ctx context.Context, batch *models.InventoryBatch) error {
        query := `
                UPDATE inventory_batches SET
                        barcode = $2,
                        cost_per_unit = $3,
                        location = $4,
                        is_reserved = $5,
                        is_quarantined = $6,
                        quarantine_reason = $7,
                        updated_at = NOW()
                WHERE id = $1
                RETURNING updated_at
        `

        err := r.pool.QueryRow(ctx, query,
                batch.ID,
                batch.Barcode,
                batch.CostPerUnit,
                batch.Location,
                batch.IsReserved,
                batch.IsQuarantined,
                batch.QuarantineReason,
        ).Scan(&batch.UpdatedAt)

        if err != nil {
                return fmt.Errorf("failed to update inventory batch: %w", err)
        }

        return nil
}

// UpdateQuantity updates the cached quantity of a batch (should match SUM of movements)
func (r *InventoryBatchRepository) UpdateQuantity(ctx context.Context, batchID string, newQuantity float64) error {
        query := `UPDATE inventory_batches SET quantity = $2, updated_at = NOW() WHERE id = $1`
        
        _, err := r.pool.Exec(ctx, query, batchID, newQuantity)
        if err != nil {
                return fmt.Errorf("failed to update batch quantity: %w", err)
        }
        
        return nil
}

// GetByBatchNumber gets a batch by its batch number within a pharmacy product
func (r *InventoryBatchRepository) GetByBatchNumber(
        ctx context.Context,
        pharmacyProductID string,
        batchNumber string,
) (*models.InventoryBatch, error) {
        query := `
                SELECT 
                        id, pharmacy_product_id, branch_id,
                        batch_number, quantity, unit,
                        cost_per_unit, total_cost,
                        expiry_date, days_until_expiry,
                        is_reserved, is_quarantined,
                        received_date, created_at
                FROM inventory_batches
                WHERE pharmacy_product_id = $1 AND batch_number = $2
        `

        batch := &models.InventoryBatch{}
        err := r.pool.QueryRow(ctx, query, pharmacyProductID, batchNumber).Scan(
                &batch.ID,
                &batch.PharmacyProductID,
                &batch.BranchID,
                &batch.BatchNumber,
                &batch.Quantity,
                &batch.Unit,
                &batch.CostPerUnit,
                &batch.TotalCost,
                &batch.ExpiryDate,
                &batch.DaysUntilExpiry,
                &batch.IsReserved,
                &batch.IsQuarantined,
                &batch.ReceivedDate,
                &batch.CreatedAt,
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get batch by number: %w", err)
        }

        return batch, nil
}

// ListExpiringSoon lists batches that will expire within N days
func (r *InventoryBatchRepository) ListExpiringSoon(
        ctx context.Context,
        pharmacyID string,
        daysThreshold int,
) ([]*models.InventoryBatch, error) {
        query := `
                SELECT 
                        ib.id, ib.pharmacy_product_id, ib.branch_id,
                        ib.batch_number, ib.quantity, ib.unit,
                        ib.cost_per_unit, ib.total_cost,
                        ib.expiry_date, ib.days_until_expiry,
                        gp.name as product_name, gp.generic_name, gp.barcode,
                        b.name as branch_name
                FROM inventory_batches ib
                JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
                JOIN global_products gp ON pp.global_product_id = gp.id
                JOIN branches b ON ib.branch_id = b.id
                WHERE pp.pharmacy_id = $1
                  AND ib.days_until_expiry IS NOT NULL
                  AND ib.days_until_expiry <= $2
                  AND ib.quantity > 0
                ORDER BY ib.days_until_expiry ASC, ib.expiry_date ASC
        `

        rows, err := r.pool.Query(ctx, query, pharmacyID, daysThreshold)
        if err != nil {
                return nil, fmt.Errorf("failed to list expiring batches: %w", err)
        }
        defer rows.Close()

        batches := make([]*models.InventoryBatch, 0)
        for rows.Next() {
                batch := &models.InventoryBatch{
                        GlobalProduct: &models.GlobalProduct{},
                        Branch:       &models.Branch{},
                }
                
                err := rows.Scan(
                        &batch.ID,
                        &batch.PharmacyProductID,
                        &batch.BranchID,
                        &batch.BatchNumber,
                        &batch.Quantity,
                        &batch.Unit,
                        &batch.CostPerUnit,
                        &batch.TotalCost,
                        &batch.ExpiryDate,
                        &batch.DaysUntilExpiry,
                        &batch.GlobalProduct.Name,
                        &batch.GlobalProduct.GenericName,
                        &batch.GlobalProduct.Barcode,
                        &batch.Branch.Name,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan expiring batch: %w", err)
                }
                batches = append(batches, batch)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating expiring batches: %w", err)
        }

        return batches, nil
}
