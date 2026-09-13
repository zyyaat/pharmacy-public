package handlers

// Test 68 — plan pricing gate: a public+active plan must carry at least one
// positive price (monthly or yearly). This is the server-side half of the
// fix for the "0 EGP → تعذر بدء الدفع" dead end: the checkout refuses
// zero-amount intentions, so the plan editor must refuse unpriced public
// plans in the first place. Private/inactive plans stay exempt (assigned
// manually or hidden from self-serve).

import "testing"

func planPayload(monthly, yearly int64) *platformPlanPayload {
	return &platformPlanPayload{
		Slug:                 "test-plan",
		Name:                 "Test Plan",
		MonthlyPricePiastres: monthly,
		YearlyPricePiastres:  yearly,
		Currency:             "EGP",
	}
}

func TestPlanValidatePricingGate(t *testing.T) {
	cases := []struct {
		name      string
		payload   *platformPlanPayload
		isActive  bool
		isPublic  bool
		wantError bool
	}{
		{
			name:      "public_active_zero_priced_rejected",
			payload:   planPayload(0, 0),
			isActive:  true,
			isPublic:  true,
			wantError: true,
		},
		{
			name:      "public_active_monthly_ok",
			payload:   planPayload(10_000, 0),
			isActive:  true,
			isPublic:  true,
			wantError: false,
		},
		{
			name:      "public_active_yearly_only_ok",
			payload:   planPayload(0, 100_000),
			isActive:  true,
			isPublic:  true,
			wantError: false,
		},
		{
			name:      "public_inactive_zero_ok",
			payload:   planPayload(0, 0),
			isActive:  false,
			isPublic:  true,
			wantError: false,
		},
		{
			name:      "private_active_zero_ok",
			payload:   planPayload(0, 0),
			isActive:  true,
			isPublic:  false,
			wantError: false,
		},
		{
			name:      "negative_price_still_rejected",
			payload:   planPayload(-1, 0),
			isActive:  true,
			isPublic:  true,
			wantError: true,
		},
		{
			name:      "public_active_missing_name_rejected",
			payload:   &platformPlanPayload{Slug: "x", MonthlyPricePiastres: 5_000},
			isActive:  true,
			isPublic:  true,
			wantError: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.payload.validate(true, tc.isActive, tc.isPublic)
			if tc.wantError && got == "" {
				t.Fatalf("expected validation error, got none")
			}
			if !tc.wantError && got != "" {
				t.Fatalf("expected no validation error, got %q", got)
			}
		})
	}
}
