package repository

import (
	"context"
	"math"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestAdjustBatchStockRejectsInvalidInputBeforeOpeningDatabase(t *testing.T) {
	repository := NewStockMovementRepository(nil)
	base := StockAdjustmentInput{
		BatchID:        "batch",
		PharmacyID:     "pharmacy",
		EmployeeID:     "employee",
		Delta:          1,
		IdempotencyKey: "adjustment-123",
	}

	tests := []struct {
		name  string
		input StockAdjustmentInput
	}{
		{"zero delta", func() StockAdjustmentInput { v := base; v.Delta = 0; return v }()},
		{"nan delta", func() StockAdjustmentInput { v := base; v.Delta = math.NaN(); return v }()},
		{"infinite delta", func() StockAdjustmentInput { v := base; v.Delta = math.Inf(1); return v }()},
		{"missing batch", func() StockAdjustmentInput { v := base; v.BatchID = ""; return v }()},
		{"short idempotency key", func() StockAdjustmentInput { v := base; v.IdempotencyKey = "short"; return v }()},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := repository.AdjustBatchStock(context.Background(), test.input)
			require.ErrorIs(t, err, ErrInvalidStockAdjustment)
		})
	}
}
