// Package jobs - Low Stock Checker Job
//
// This job monitors inventory levels and identifies items that have fallen
// below their minimum stock threshold, triggering reorder alerts.
//
// Trigger: On stock changes OR periodic check (configurable)
// Action: Query medications where quantity <= min_stock_level
// Output: Send low-stock alerts, create purchase recommendations

package jobs

import (
	"context"
	"time"
)

// LowStockCheckerWorker handles low stock level monitoring
// TODO: Implement with River JobArgs interface
type LowStockCheckerWorker struct {
	PharmacyID string `json:"pharmacy_id"`
}

// LowStockItem represents a medication that is below minimum stock
type LowStockItem struct {
	MedicationID   string  `json:"medication_id"`
	Name           string  `json:"name"`
	SKU            string  `json:"sku"`
	CurrentQuantity int   `json:"current_quantity"`
	MinStockLevel  int    `json:"min_stock_level"`
	Shortage       int    `json:"shortage"` // min_stock - current
}

// LowStockCheckResult holds the results of a low stock check
type LowStockCheckResult struct {
	PharmacyID    string          `json:"pharmacy_id"`
	CheckedAt     time.Time       `json:"checked_at"`
	LowStockItems []LowStockItem  `json:"low_stock_items"`
	TotalItemsAffected int        `json:"total_items_affected"`
}

// Run executes the low stock check job
// TODO: Implement actual logic:
// 1. Query all medications for the pharmacy
// 2. Filter WHERE quantity <= min_stock_level
// 3. Calculate shortage amounts
// 4. Generate alert report
// 5. Trigger notification job if items found
func (w *LowStockCheckerWorker) Run(ctx context.Context) (*LowStockCheckResult, error) {
	// Placeholder implementation
	_ = ctx
	
	return &LowStockCheckResult{
		PharmacyID:         w.PharmacyID,
		CheckedAt:          time.Now(),
		LowStockItems:      []LowStockItem{},
		TotalItemsAffected: 0,
	}, nil
}
