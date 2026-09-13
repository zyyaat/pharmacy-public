package paymob

import (
        "context"
        "encoding/json"
        "io"
        "net/http"
        "net/http/httptest"
        "strings"
        "testing"
)

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

// Wire-contract guard: the intention request must go to POST {base}/v1/intention/
// (integration ID inside the body, never in the URL) with the amount in
// integer piastres/cents — matches Paymob's official samples. This test
// exists because the real endpoint answers a wrong path with an HTML 404
// that only shows up in production logs.
func TestCreateIntentionWireContract(t *testing.T) {
        var gotPath, gotAuth string
        var gotBody map[string]any
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                gotPath = r.URL.Path
                gotAuth = r.Header.Get("Authorization")
                raw, _ := io.ReadAll(r.Body)
                _ = json.Unmarshal(raw, &gotBody)
                w.Header().Set("Content-Type", "application/json")
                _, _ = w.Write([]byte(`{"client_secret":"csk_test_abc","intention_order_id":777000,"id":42,"status":"intended"}`))
        }))
        defer srv.Close()

        c := New("sk_test_secret", "pk_test_public", "456987", "", srv.URL)
        resp, err := c.CreateIntention(context.Background(), IntentionRequest{
                AmountPiastres:   12500, // 125.00 EGP
                Currency:         "EGP",
                SpecialReference: "pay-uuid-1",
                NotificationURL:  "https://api.example.com/api/v1/payments/webhook/paymob?token=t",
                ItemName:         "Plan X",
                ItemDescription:  "اشتراك شهري — Plan X",
                BillingFirstName: "صيدلية",
        })
        if err != nil {
                t.Fatalf("CreateIntention failed: %v", err)
        }
        if gotPath != "/v1/intention/" {
                t.Fatalf("intention path = %q, want /v1/intention/", gotPath)
        }
        if gotAuth != "Token sk_test_secret" {
                t.Fatalf("auth header = %q, want Token scheme", gotAuth)
        }
        // amount must be integer piastres/cents — never divided to major units
        if amount, ok := gotBody["amount"].(float64); !ok || amount != 12500 {
                t.Fatalf("body amount = %v, want 12500 (cents)", gotBody["amount"])
        }
        methods, _ := gotBody["payment_methods"].([]any)
        if len(methods) != 1 || methods[0].(float64) != 456987 {
                t.Fatalf("payment_methods = %v, want [456987]", gotBody["payment_methods"])
        }
        billing, _ := gotBody["billing_data"].(map[string]any)
        if billing["country"] != "EGY" {
                t.Fatalf("billing country = %v, want EGY (3-letter ISO)", billing["country"])
        }
        if gotBody["notification_url"] == "" || gotBody["special_reference"] != "pay-uuid-1" {
                t.Fatalf("notification_url/special_reference missing: %v", gotBody)
        }
        if resp.ClientSecret != "csk_test_abc" || resp.IntentionOrderID != 777000 {
                t.Fatalf("response parse = %+v", resp)
        }
}

// One bad OPTIONAL channel (e.g. a stale wallet integration ID) fails the
// whole intention with 404 "Integration ID does not exist" — Paymob
// validates every payment_methods entry. The client must retry once with
// the card channel alone instead of blocking payments.
func TestCreateIntentionRetriesCardOnlyOn404(t *testing.T) {
        calls := 0
        var secondCallMethods []any
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                calls++
                var body map[string]any
                raw, _ := io.ReadAll(r.Body)
                _ = json.Unmarshal(raw, &body)
                if calls == 1 {
                        w.Header().Set("Content-Type", "application/json")
                        w.WriteHeader(http.StatusNotFound)
                        _, _ = w.Write([]byte(`{"detail":"Integration ID does not exist in our system"}`))
                        return
                }
                secondCallMethods = body["payment_methods"].([]any)
                w.Header().Set("Content-Type", "application/json")
                _, _ = w.Write([]byte(`{"client_secret":"csk_retry_ok","intention_order_id":99}`))
        }))
        defer srv.Close()

        c := New("sk_test_secret", "pk_test_public", "456987", "111222", srv.URL) // card + (bad) wallet
        resp, err := c.CreateIntention(context.Background(), IntentionRequest{
                AmountPiastres: 10000,
                Currency:       "EGP",
                ItemName:       "Plan",
        })
        if err != nil {
                t.Fatalf("retry path failed: %v", err)
        }
        if calls != 2 {
                t.Fatalf("calls = %d, want 2 (original + card-only retry)", calls)
        }
        if len(secondCallMethods) != 1 || secondCallMethods[0].(float64) != 456987 {
                t.Fatalf("retry payment_methods = %v, want [456987] card only", secondCallMethods)
        }
        if resp.ClientSecret != "csk_retry_ok" || resp.IntentionOrderID != 99 {
                t.Fatalf("resp = %+v", resp)
        }
}

// Locks the diagnostic probe wire contract: POST {base}/api/auth/tokens
// with the API key → Bearer token → GET {base}/api/ecommerce/integrations.
// This probe exists to settle "Integration ID does not exist" disputes by
// listing the IDs that really exist on the account.
func TestProbeAccountIntegrationsWireContract(t *testing.T) {
        var listPath, listAuth string
        var authBody map[string]any
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                switch {
                case r.URL.Path == "/api/auth/tokens":
                        raw, _ := io.ReadAll(r.Body)
                        _ = json.Unmarshal(raw, &authBody)
                        w.Header().Set("Content-Type", "application/json")
                        _, _ = w.Write([]byte(`{"token":"diag_tok_123"}`))
                default:
                        listPath = r.URL.Path
                        listAuth = r.Header.Get("Authorization")
                        w.Header().Set("Content-Type", "application/json")
                        _, _ = w.Write([]byte(`[{"id":4586083,"name":"Online Card"},{"id":4801234,"name":"Mobile Wallet"}]`))
                }
        }))
        defer srv.Close()

        c := New("sk_x", "pk_x", "4586083", "", srv.URL)
        probe, err := c.ProbeAccountIntegrations(context.Background(), "diag_api_key")
        if err != nil {
                t.Fatalf("ProbeAccountIntegrations failed: %v", err)
        }
        if authBody["api_key"] != "diag_api_key" {
                t.Fatalf("auth body api_key = %v", authBody["api_key"])
        }
        if listPath != "/api/ecommerce/integrations" {
                t.Fatalf("list path = %q", listPath)
        }
        if listAuth != "Bearer diag_tok_123" {
                t.Fatalf("list auth = %q, want Bearer token from auth/tokens", listAuth)
        }
        if probe["path"] != "/api/ecommerce/integrations" {
                t.Fatalf("probe path = %v", probe["path"])
        }
        ids := map[int64]bool{}
        for _, item := range probe["integrations"].([]any) {
                obj := item.(map[string]any)
                ids[int64(obj["id"].(float64))] = true
        }
        if !ids[4586083] || !ids[4801234] {
                t.Fatalf("probe ids = %v, want both listed", ids)
        }
}

// A rejected API key must surface as a probe error (never silently empty).
func TestProbeAccountIntegrationsRejectsBadKey(t *testing.T) {
        srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.WriteHeader(http.StatusUnauthorized)
                _, _ = w.Write([]byte(`{"detail":"Invalid api key"}`))
        }))
        defer srv.Close()

        c := New("sk_x", "pk_x", "123", "", srv.URL)
        if _, err := c.ProbeAccountIntegrations(context.Background(), "wrong_key"); err == nil {
                t.Fatalf("bad API key must error, got nil")
        }
}

// Locks the concatenation to Paymob's OFFICIAL worked example
// (hmac-verification.md): exact field order + value rendering must produce
// the exact documented string before any hash is trusted.
func TestHMACConcatenationMatchesPaymobDocsExample(t *testing.T) {
        obj := map[string]any{
                "amount_cents":          float64(100),
                "created_at":            "2020-03-25T18:39:44.719228",
                "currency":              "EGP",
                "error_occured":         false,
                "has_parent_transaction": false,
                "id":                    float64(2556706),
                "integration_id":        float64(6741),
                "is_3d_secure":          true,
                "is_auth":               false,
                "is_capture":            false,
                "is_refunded":           false,
                "is_standalone_payment": true,
                "is_voided":             false,
                "order": map[string]any{"id": float64(4778239)},
                "owner":                 float64(4705),
                "pending":               false,
                "source_data": map[string]any{
                        "pan":      "2346",
                        "sub_type": "MasterCard",
                        "type":     "card",
                },
                "success": true,
        }
        var b strings.Builder
        for _, f := range hmacFieldOrder {
                b.WriteString(hmacValue(hmacLookup(obj, f)))
        }
        const want = "1002020-03-25T18:39:44.719228EGPfalsefalse25567066741truefalsefalsefalsetruefalse47782394705false2346MasterCardcardtrue"
        if got := b.String(); got != want {
                t.Fatalf("concat mismatch:\n got  %s\n want %s", got, want)
        }
}
