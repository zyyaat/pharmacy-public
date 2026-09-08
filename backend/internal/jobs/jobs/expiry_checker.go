// Package jobs - Expiry Checker Job
//
// This job periodically checks for medications approaching expiry date
// and triggers alerts/notifications when items are close to expiring.
//
// Trigger: Daily cron job (configurable frequency)
// Action: Query medications where expiry_date <= NOW() + threshold
// Output: Send notifications, update dashboard alerts

package jobs

import (
	"context"
	"time"
)

// ExpiryCheckerWorker handles medication expiry checking
// TODO: Implement with River JobArgs interface
type ExpiryCheckerWorker struct {
	PharmacyID string    `json:"pharmacy_id"`
	DaysThreshold int   `json:"days_threshold"`
}

// ExpiryCheckResult holds the results of an expiry check run
type ExpiryCheckResult struct {
	PharmacyID      string    `json:"pharmacy_id"`
	CheckedAt       time.Time `json:"checked_at"`
	ExpiringSoonCount int    `json:"expiring_soon_count"`
	ExpiredCount    int       `json:"expired_count"`
}

// Run executes the expiry check job
// TODO: Implement actual logic:
// 1. Query medications for the pharmacy
// 2. Filter by expiry_date <= NOW() + DaysThreshold
// 3. Categorize as "expiring soon" or "expired"
// 4. Record results and trigger notifications
func (w *ExpiryCheckerWorker) Run(ctx context.Context) (*ExpiryCheckResult, error) {
	// Placeholder implementation
	_ = ctx
	
	return &ExpiryCheckResult{
		PharmacyID:     w.PharmacyID,
		CheckedAt:      time.Now(),
		ExpiringSoonCount: 0,
		ExpiredCount:   0,
	}, nil
}
