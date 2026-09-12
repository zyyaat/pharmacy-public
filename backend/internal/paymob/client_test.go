package paymob

import "testing"

// Golden vector computed independently (Python hmac/sha512) over the
// documented Paymob field order — guards against any reordering or
// value-rendering regression in VerifyTransactionHMAC.
func TestVerifyTransactionHMACGolden(t *testing.T) {
	obj := map[string]any{
		"amount_cents":          float64(12500),
		"created_at":            "2026-09-13T10:00:00.000000",
		"currency":              "EGP",
		"error_occured":         false,
		"has_parent_transaction": false,
		"id":                    float64(987654321),
		"integration_id":        float64(4801234),
		"is_3d_secure":          true,
		"is_auth":               false,
		"is_capture":            false,
		"is_refunded":           false,
		"is_standalone_payment": false,
		"is_voided":             false,
		"order": map[string]any{
			"id":                float64(111222333),
			"merchant_order_id": "abc-payment-uuid",
		},
		"owner":   float64(555000),
		"pending": false,
		"source_data": map[string]any{
			"pan":      "2346",
			"sub_type": "MasterCard",
			"type":     "card",
		},
		"success": true,
	}
	const secret = "test_hmac_secret_phase_g"
	const good = "2b86fde4f7e912714167e5ec63fc46ea034c2e85d4deb53b38ce1e3abc3fb1807876b1eecae587e060cb2a81e59c78e936c5d04f0a1900ab813e37bfa1120261"

	if !VerifyTransactionHMAC(obj, good, secret) {
		t.Fatalf("valid HMAC rejected")
	}
	if VerifyTransactionHMAC(obj, good+"ff", secret) {
		t.Fatalf("tampered HMAC accepted")
	}
	if VerifyTransactionHMAC(obj, good, "wrong-secret") {
		t.Fatalf("HMAC from another secret accepted")
	}
	// amount tampering must invalidate the signature
	tampered := map[string]any{}
	for k, v := range obj {
		tampered[k] = v
	}
	tampered["amount_cents"] = float64(1)
	if VerifyTransactionHMAC(tampered, good, secret) {
		t.Fatalf("tampered amount accepted")
	}
	if VerifyTransactionHMAC(nil, good, secret) || VerifyTransactionHMAC(obj, "", secret) {
		t.Fatalf("empty inputs must fail closed")
	}
}

// Numbers arrive as float64 from encoding/json — 12500 must render as
// "12500" (never scientific notation) inside the concatenation.
func TestHMACValueRendering(t *testing.T) {
	if got := hmacValue(float64(12500)); got != "12500" {
		t.Fatalf("float64 render = %q", got)
	}
	if got := hmacValue(float64(12500.5)); got != "12500.5" {
		t.Fatalf("decimal render = %q", got)
	}
	if got := hmacValue(true); got != "true" {
		t.Fatalf("bool render = %q", got)
	}
	if got := hmacValue(nil); got != "" {
		t.Fatalf("nil render = %q", got)
	}
}
