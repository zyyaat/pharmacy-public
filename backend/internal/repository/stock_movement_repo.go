// Package repository provides database access for Stock Movements
// This handles the SOURCE OF TRUTH for all inventory quantity changes
package repository

import (
        "context"
        "fmt"
        "time"

        "github.com/jackc/pgx/v5/pgxpool"

        "github.com/pharmacy-os/backend/internal/models"
)

// StockMovementRepository handles database operations for stock movements
type StockMovementRepository struct {
        pool *pgxpool.Pool
}

// NewStockMovementRepository creates a new stock movement repository
func NewStockMovementRepository(pool *pgxpool.Pool) *StockMovementRepository {
        return &StockMovementRepository{pool: pool}
}

// Create creates a new stock movement record
// IMPORTANT: This should be called within a transaction that also updates the batch quantity
func (r *StockMovementRepository) Create(ctx context.Context, movement *models.StockMovement) error {
        query := `
                INSERT INTO stock_movements (
                        batch_id,
                        movement_type, quantity, unit,
                        reference_type, reference_id,
                        quantity_before, quantity_after,
                        unit_cost, total_cost,
                        created_by,
                        reason, notes,
                        ip_address, user_agent
                ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
                )
                RETURNING id, created_at
        `

        err := r.pool.QueryRow(ctx, query,
                movement.BatchID,
                movement.MovementType,
                movement.Quantity,
                movement.Unit,
                movement.ReferenceType,
                movement.ReferenceID,
                movement.QuantityBefore,
                movement.QuantityAfter,
                movement.UnitCost,
                movement.TotalCost,
                movement.CreatedBy,
                movement.Reason,
                movement.Notes,
                movement.IPAddress,
                movement.UserAgent,
        ).Scan(&movement.ID, &movement.CreatedAt)

        if err != nil {
                return fmt.Errorf("failed to create stock movement: %w", err)
        }

        return nil
}

// GetByID retrieves a stock movement by ID with joined data
func (r *StockMovementRepository) GetByID(ctx context.Context, id string) (*models.StockMovement, error) {
        query := `
                SELECT 
                        sm.id, sm.batch_id,
                        sm.movement_type, sm.quantity, sm.unit,
                        sm.reference_type, sm.reference_id,
                        sm.quantity_before, sm.quantity_after,
                        sm.unit_cost, sm.total_cost,
                        sm.created_by,
                        sm.reason, sm.notes,
                        sm.ip_address, sm.user_agent,
                        sm.created_at,
                        gp.name as product_name, gp.generic_name,
                        ib.batch_number,
                        CONCAT(e.first_name, ' ', e.last_name) as created_by_name
                FROM stock_movements sm
                JOIN inventory_batches ib ON sm.batch_id = ib.id
                JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
                JOIN global_products gp ON pp.global_product_id = gp.id
                LEFT JOIN employees e ON sm.created_by = e.id
                WHERE sm.id = $1
        `

        movement := &models.StockMovement{
                Batch:             &models.InventoryBatch{},
                CreatedByEmployee:  &models.Employee{},
        }
        
        err := r.pool.QueryRow(ctx, query, id).Scan(
                &movement.ID,
                &movement.BatchID,
                &movement.MovementType,
                &movement.Quantity,
                &movement.Unit,
                &movement.ReferenceType,
                &movement.ReferenceID,
                &movement.QuantityBefore,
                &movement.QuantityAfter,
                &movement.UnitCost,
                &movement.TotalCost,
                &movement.CreatedBy,
                &movement.Reason,
                &movement.Notes,
                &movement.IPAddress,
                &movement.UserAgent,
                &movement.CreatedAt,
                &movement.Batch.BatchNumber,
                &movement.CreatedByEmployee.FirstName, // Will contain full name due to CONCAT
        )

        if err != nil {
                return nil, fmt.Errorf("failed to get stock movement by ID %s: %w", id, err)
        }

        return movement, nil
}

// ListByBatch lists all movements for a specific batch
func (r *StockMovementRepository) ListByBatch(
        ctx context.Context,
        batchID string,
        limit int,
) ([]*models.StockMovement, error) {
        if limit == 0 || limit > 1000 {
                limit = 100 // Default limit to prevent excessive data loading
        }

        query := `
                SELECT 
                        sm.id, sm.batch_id,
                        sm.movement_type, sm.quantity, sm.unit,
                        sm.reference_type, reference_id,
                        sm.quantity_before, sm.quantity_after,
                        sm.created_by, sm.reason, sm.notes,
                        sm.created_at,
                        CONCAT(e.first_name, ' ', e.last_name) as created_by_name
                FROM stock_movements sm
                LEFT JOIN employees e ON sm.created_by = e.id
                WHERE sm.batch_id = $1
                ORDER BY sm.created_at DESC
                LIMIT $2
        `

        rows, err := r.pool.Query(ctx, query, batchID, limit)
        if err != nil {
                return nil, fmt.Errorf("failed to list movements for batch %s: %w", batchID, err)
        }
        defer rows.Close()

        movements := make([]*models.StockMovement, 0)
        for rows.Next() {
                movement := &models.StockMovement{
                        CreatedByEmployee: &models.Employee{},
                }
                
                var createdByName *string
                
                err := rows.Scan(
                        &movement.ID,
                        &movement.BatchID,
                        &movement.MovementType,
                        &movement.Quantity,
                        &movement.Unit,
                        &movement.ReferenceType,
                        &movement.ReferenceID,
                        &movement.QuantityBefore,
                        &movement.QuantityAfter,
                        &movement.CreatedBy,
                        &movement.Reason,
                        &movement.Notes,
                        &movement.CreatedAt,
                        &createdByName,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan stock movement: %w", err)
                }
                
                if createdByName != nil {
                        movement.CreatedByEmployee.FirstName = *createdByName
                }
                
                movements = append(movements, movement)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating stock movements: %w", err)
        }

        return movements, nil
}

// ListByReference lists all movements for a specific reference (e.g., purchase order, sale)
func (r *StockMovementRepository) ListByReference(
        ctx context.Context,
        referenceType string,
        referenceID string,
) ([]*models.StockMovement, error) {
        query := `
                SELECT 
                        sm.id, sm.batch_id,
                        sm.movement_type, sm.quantity, sm.unit,
                        sm.quantity_before, sm.quantity_after,
                        sm.created_by, sm.created_at,
                        gp.name as product_name, ib.batch_number
                FROM stock_movements sm
                JOIN inventory_batches ib ON sm.batch_id = ib.id
                JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
                JOIN global_products gp ON pp.global_product_id = gp.id
                WHERE sm.reference_type = $1 AND sm.reference_id = $2
                ORDER BY sm.created_at ASC
        `

        rows, err := r.pool.Query(ctx, query, referenceType, referenceID)
        if err != nil {
                return nil, fmt.Errorf("failed to list movements for reference: %w", err)
        }
        defer rows.Close()

        movements := make([]*models.StockMovement, 0)
        for rows.Next() {
                movement := &models.StockMovement{
                        Batch:        &models.InventoryBatch{},
                }

                err := rows.Scan(
                        &movement.ID,
                        &movement.BatchID,
                        &movement.MovementType,
                        &movement.Quantity,
                        &movement.Unit,
                        &movement.QuantityBefore,
                        &movement.QuantityAfter,
                        &movement.CreatedBy,
                        &movement.CreatedAt,
                        &movement.Batch.BatchNumber,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan stock movement by reference: %w", err)
                }
                movements = append(movements, movement)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating stock movements by reference: %w", err)
        }

        return movements, nil
}

// CalculateCurrentStock calculates the current stock for a batch by summing all movements
// This is the authoritative source of truth for batch quantities
func (r *StockMovementRepository) CalculateCurrentStock(ctx context.Context, batchID string) (float64, error) {
        query := `SELECT COALESCE(SUM(quantity), 0) FROM stock_movements WHERE batch_id = $1`
        
        var currentStock float64
        err := r.pool.QueryRow(ctx, query, batchID).Scan(&currentStock)
        if err != nil {
                return 0, fmt.Errorf("failed to calculate current stock for batch %s: %w", batchID, err)
        }
        
        return currentStock, nil
}

// CalculateProductTotalStock calculates total stock across all batches for a pharmacy product
func (r *StockMovementRepository) CalculateProductTotalStock(
        ctx context.Context,
        pharmacyProductID string,
        branchID *string,
) (float64, error) {
        var query string
        args := []interface{}{pharmacyProductID}
        
        if branchID != nil && *branchID != "" {
                query = `
                        SELECT COALESCE(SUM(sm.quantity), 0)
                        FROM stock_movements sm
                        JOIN inventory_batches ib ON sm.batch_id = ib.id
                        WHERE ib.pharmacy_product_id = $1 AND ib.branch_id = $2
                `
                args = append(args, *branchID)
        } else {
                query = `
                        SELECT COALESCE(SUM(sm.quantity), 0)
                        FROM stock_movements sm
                        JOIN inventory_batches ib ON sm.batch_id = ib.id
                        WHERE ib.pharmacy_product_id = $1
                `
        }
        
        var totalStock float64
        err := r.pool.QueryRow(ctx, query, args...).Scan(&totalStock)
        if err != nil {
                return 0, fmt.Errorf("failed to calculate total stock for product %s: %w", pharmacyProductID, err)
        }
        
        return totalStock, nil
}

// ListRecent lists recent stock movements with filtering options
func (r *StockMovementRepository) ListRecent(
        ctx context.Context,
        pharmacyID string,
        movementType *string,
        limit int,
) ([]*models.StockMovement, error) {
        if limit == 0 || limit > 500 {
                limit = 50
        }

        baseQuery := `
                SELECT 
                        sm.id, sm.batch_id,
                        sm.movement_type, sm.quantity, sm.unit,
                        sm.quantity_before, sm.quantity_after,
                        sm.created_by, sm.reason,
                        sm.created_at,
                        gp.name as product_name, gp.barcode,
                        ib.batch_number,
                        b.name as branch_name,
                        CONCAT(e.first_name, ' ', e.last_name) as created_by_name
                FROM stock_movements sm
                JOIN inventory_batches ib ON sm.batch_id = ib.id
                JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
                JOIN global_products gp ON pp.global_product_id = gp.id
                LEFT JOIN branches b ON ib.branch_id = b.id
                LEFT JOIN employees e ON sm.created_by = e.id
                WHERE pp.pharmacy_id = $1
        `

        args := []interface{}{pharmacyID}
        argNum := 2

        if movementType != nil && *movementType != "" {
                baseQuery += fmt.Sprintf(" AND sm.movement_type = $%d", argNum)
                args = append(args, *movementType)
                argNum++
        }

        baseQuery += " ORDER BY sm.created_at DESC LIMIT " + fmt.Sprintf("$%d", argNum)
        args = append(args, limit)

        rows, err := r.pool.Query(ctx, baseQuery, args...)
        if err != nil {
                return nil, fmt.Errorf("failed to list recent stock movements: %w", err)
        }
        defer rows.Close()

        movements := make([]*models.StockMovement, 0)
        for rows.Next() {
                movement := &models.StockMovement{
                        Batch:            &models.InventoryBatch{},
                        CreatedByEmployee: &models.Employee{},
                }

                var createdByName *string

                err := rows.Scan(
                        &movement.ID,
                        &movement.BatchID,
                        &movement.MovementType,
                        &movement.Quantity,
                        &movement.Unit,
                        &movement.QuantityBefore,
                        &movement.QuantityAfter,
                        &movement.CreatedBy,
                        &movement.Reason,
                        &movement.CreatedAt,
                        &movement.Batch.BatchNumber,
                        &createdByName,
                )
                if err != nil {
                        return nil, fmt.Errorf("failed to scan recent stock movement: %w", err)
                }
                
                if createdByName != nil {
                        movement.CreatedByEmployee.FirstName = *createdByName
                }
                
                movements = append(movements, movement)
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating recent stock movements: %w", err)
        }

        return movements, nil
}

// GetMovementSummary returns summary statistics for movements in a date range
func (r *StockMovementRepository) GetMovementSummary(
        ctx context.Context,
        pharmacyID string,
        startDate, endDate time.Time,
) (map[string]float64, error) {
        query := `
                SELECT 
                        sm.movement_type,
                        COUNT(*) as movement_count,
                        COALESCE(SUM(CASE WHEN sm.quantity > 0 THEN sm.quantity ELSE 0 END), 0) as total_in,
                        COALESCE(SUM(CASE WHEN sm.quantity < 0 THEN ABS(sm.quantity) ELSE 0 END), 0) as total_out
                FROM stock_movements sm
                JOIN inventory_batches ib ON sm.batch_id = ib.id
                JOIN pharmacy_products pp ON ib.pharmacy_product_id = pp.id
                WHERE pp.pharmacy_id = $1 
                  AND sm.created_at BETWEEN $2 AND $3
                GROUP BY sm.movement_type
        `

        rows, err := r.pool.Query(ctx, query, pharmacyID, startDate, endDate)
        if err != nil {
                return nil, fmt.Errorf("failed to get movement summary: %w", err)
        }
        defer rows.Close()

        summary := make(map[string]float64)
        for rows.Next() {
                var movementType string
                var count, totalIn, totalOut float64
                
                err := rows.Scan(&movementType, &count, &totalIn, &totalOut)
                if err != nil {
                        return nil, fmt.Errorf("failed to scan movement summary row: %w", err)
                }
                
                summary[movementType+".count"] = count
                summary[movementType+".in"] = totalIn
                summary[movementType+".out"] = totalOut
        }

        if err := rows.Err(); err != nil {
                return nil, fmt.Errorf("error iterating movement summary: %w", err)
        }

        return summary, nil
}
