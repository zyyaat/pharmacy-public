// Shared billing transition (Task 90 Phase G).
//
// applySucceededPaymentTx is the ONE subscription transition performed for
// ANY succeeded payment — a super-admin manual registration or a verified
// Paymob webhook. Keeping it in a single place guarantees the payment
// provider never changes billing semantics:
//
//   - live subscription already active on the SAME plan  → extend the period;
//   - running trial on the SAME plan                     → convert to active;
//   - anything else (different plan, pending, expired…)  → replace/insert.
//
// It also links payments.subscription_id and keeps the legacy display
// columns (companies.plan / companies.status) in sync. Must run inside an
// open transaction; the caller owns commit + cache invalidation.
package handlers

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/pharmacy-os/backend/internal/models"
)

func applySucceededPaymentTx(
	ctx context.Context,
	tx pgx.Tx,
	companyID, planID, billingInterval, paymentID string,
) (string, error) {
	periodStart := time.Now()
	var periodEnd time.Time
	if billingInterval == models.BillingIntervalYearly {
		periodEnd = periodStart.AddDate(1, 0, 0)
	} else {
		periodEnd = periodStart.AddDate(0, 1, 0)
	}

	var subscriptionID, existingStatus, existingPlanID string
	err := tx.QueryRow(ctx, `
		SELECT s.id::text, s.status, s.plan_id::text
		FROM subscriptions s
		WHERE s.company_id = $1 AND s.status IN ('trial','active','pending')
		ORDER BY s.created_at DESC LIMIT 1
	`, companyID).Scan(&subscriptionID, &existingStatus, &existingPlanID)

	switch {
	case err == nil && existingStatus == models.SubStatusActive && existingPlanID == planID:
		// renewal: extend from the later of (period end, now)
		if _, err := tx.Exec(ctx, `
			UPDATE subscriptions
			SET current_period_start = $2,
			    current_period_end = GREATEST(COALESCE(current_period_end, NOW()), NOW()) +
			        CASE $3 WHEN 'yearly' THEN INTERVAL '1 year' ELSE INTERVAL '1 month' END,
			    cancel_at_period_end = FALSE, updated_at = NOW()
			WHERE id = $1
		`, subscriptionID, periodStart, billingInterval); err != nil {
			return "", fmt.Errorf("extend subscription: %w", err)
		}
	case err == nil && existingStatus == models.SubStatusTrial && existingPlanID == planID:
		// convert the running trial into a paid period
		if _, err := tx.Exec(ctx, `
			UPDATE subscriptions
			SET status = 'active', billing_interval = $2,
			    current_period_start = $3, current_period_end = $4,
			    trial_ends_at = NULL, updated_at = NOW()
			WHERE id = $1
		`, subscriptionID, billingInterval, periodStart, periodEnd); err != nil {
			return "", fmt.Errorf("convert trial: %w", err)
		}
	default:
		if err == nil {
			// a live row exists for a different plan (or pending) — replace it
			if _, err := tx.Exec(ctx, `
				UPDATE subscriptions SET status = 'cancelled', updated_at = NOW()
				WHERE id = $1
			`, subscriptionID); err != nil {
				return "", fmt.Errorf("replace subscription: %w", err)
			}
		}
		if err := tx.QueryRow(ctx, `
			INSERT INTO subscriptions
			    (company_id, plan_id, status, billing_interval,
			     current_period_start, current_period_end, source)
			VALUES ($1, $2, 'active', $3, $4, $5, 'payment')
			RETURNING id::text
		`, companyID, planID, billingInterval, periodStart, periodEnd).Scan(&subscriptionID); err != nil {
			return "", fmt.Errorf("insert subscription: %w", err)
		}
	}

	if _, err := tx.Exec(ctx, `
		UPDATE payments SET subscription_id = $2, updated_at = NOW() WHERE id = $1
	`, paymentID, subscriptionID); err != nil {
		return "", fmt.Errorf("link payment: %w", err)
	}

	// legacy display columns stay in sync (deprecated but visible)
	if _, err := tx.Exec(ctx, `
		UPDATE companies SET plan = (
		        SELECT slug::text FROM plans WHERE id = $2
		), status = 'active', updated_at = NOW()
		WHERE id = $1
	`, companyID, planID); err != nil {
		return "", fmt.Errorf("sync company display: %w", err)
	}

	return subscriptionID, nil
}
