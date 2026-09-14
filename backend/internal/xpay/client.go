// Package xpay — server-side client for the XPay Checkout Sessions API
// (https://docs.xpay.app). This is the replacement gateway for Paymob
// (Phase X): the activation semantics are IDENTICAL — the webhook is the
// ONLY trusted activation path, the client-side result is UI-only.
//
// Flow contract:
//
//	Backend   POST {base}/checkout/sessions
//	          Authorization: Bearer <sk_test_/sk_live_>            (server-only)
//	          Idempotency-Key: <our payments.id>                   (safe retries)
//	          uiMode            = "embedded" (web inline drop-in)
//	                              | "hosted"   (mobile WebView / legacy clients)
//	          mode              = "payment"
//	          lineItems         = [1 item, unitAmount in PIASTRES]
//	          afterCompletion   = {type:"redirect", redirect:{url}}  (required)
//	          metadata          = {payment_id: <our payments.id>}    (anchor)
//	          ← 201 { id, clientSecret, url(hosted only), amountTotal, currency }
//	Frontend  web:     XPay(publishable_key).checkout({clientSecret,
//	                   mode:"inline", container})  — iframe on our domain,
//	                   card data never touches our servers (PCI on XPay).
//	          mobile:  WebView loads the hosted session `url` (embed_url).
//	Webhook   POST /api/v1/payments/webhook/xpay
//	          XPay-Signature: t=<unix>,v1=<hex(HMAC-SHA256(secret,"t."+rawBody))>
//	          verified server-side with the endpoint's whsec_* — the ONLY
//	          activation path. Fulfil ONLY on paymentStatus == "paid"
//	          (checkout.session.completed | checkout.session.async_payment_succeeded);
//	          a `completed` session with paymentStatus "unpaid" is a Fawry-style
//	          reference still waiting — never fulfil and never fail it.
//
// The frontend never proves a payment; it only renders state.
package xpay

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const defaultTimeout = 20 * time.Second

// signatureToleranceSeconds is XPay's documented replay window: reject
// deliveries whose signature timestamp drifts more than 5 minutes.
const signatureToleranceSeconds = 300

// Client is a thin Checkout Sessions API client built from the env config.
type Client struct {
	SecretKey      string // sk_test_* / sk_live_* — server-only credential
	PublishableKey string // pk_test_* / pk_live_* — safe for the browser SDK
	BaseURL        string // e.g. https://api.xpay.app
	HTTP           *http.Client
}

// New builds a client from the loaded config values.
func New(secretKey, publishableKey, baseURL string) *Client {
	return &Client{
		SecretKey:      secretKey,
		PublishableKey: publishableKey,
		BaseURL:        baseURL,
		HTTP:           &http.Client{Timeout: defaultTimeout},
	}
}

// SessionRequest is the server-side checkout session we create per attempt.
type SessionRequest struct {
	UIMode          string // "embedded" (web inline) | "hosted" (mobile/legacy)
	AmountPiastres  int64  // smallest currency unit — XPay: piasters for EGP (10000 = 100 EGP)
	Currency        string // e.g. EGP
	PaymentID       string // our payments.id — goes into metadata AND Idempotency-Key
	RedirectURL     string // afterCompletion.redirect.url ({CHECKOUT_SESSION_ID} supported)
	ItemName        string // plan display name
	ItemDescription string // "اشتراك شهري — خطة X"
	CustomerName    string
	CustomerEmail   string
	Locale          string // "en" | "ar" (optional — omitted = account default)
}

// SessionResponse carries the fields we persist + the frontend contract.
type SessionResponse struct {
	ID            string // cs_test_* / cs_live_* — stored on payments.provider_reference
	ClientSecret  string // scopes the browser SDK to THIS session (embedded)
	URL           string // hosted checkout URL (hosted uiMode) — mobile embed_url
	AmountTotal   int64
	Currency      string
	Status        string // open | complete | expired
	PaymentStatus string // paid | unpaid | no_payment_required
	Raw           map[string]any
}

// CreateCheckoutSession calls POST {base}/checkout/sessions.
func (c *Client) CreateCheckoutSession(ctx context.Context, req SessionRequest) (*SessionResponse, error) {
	if c.SecretKey == "" {
		return nil, fmt.Errorf("xpay: missing secret key")
	}
	if req.UIMode != "embedded" && req.UIMode != "hosted" {
		req.UIMode = "hosted" // legacy-safe default: always yields a loadable URL
	}

	productData := map[string]any{"name": req.ItemName}
	if req.ItemDescription != "" {
		productData["description"] = req.ItemDescription
	}
	body := map[string]any{
		"uiMode": req.UIMode,
		"mode":   "payment",
		"afterCompletion": map[string]any{
			"type":     "redirect",
			"redirect": map[string]any{"url": req.RedirectURL},
		},
		"lineItems": []any{map[string]any{
			"priceData": map[string]any{
				"currency":    req.Currency,
				"unitAmount":  req.AmountPiastres,
				"productData": productData,
			},
			"quantity": 1,
		}},
		// The webhook anchor: data.object.metadata.payment_id on every
		// event this session ever produces.
		"metadata": map[string]any{"payment_id": req.PaymentID},
	}
	details := map[string]any{}
	if req.CustomerName != "" {
		details["name"] = req.CustomerName
	}
	if req.CustomerEmail != "" {
		details["email"] = req.CustomerEmail
	}
	if len(details) > 0 {
		body["customerDetails"] = details
	}
	if req.Locale == "en" || req.Locale == "ar" {
		body["locale"] = req.Locale
	}

	payload, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("xpay: marshal session: %w", err)
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+"/checkout/sessions", bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("xpay: build request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+c.SecretKey)
	// XPay honours write idempotency: a network retry of the same session
	// creation must never bill twice — key it on our payment id.
	httpReq.Header.Set("Idempotency-Key", req.PaymentID)

	httpResp, err := c.HTTP.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("xpay: session call failed: %w", err)
	}
	defer httpResp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(httpResp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("xpay: read session response: %w", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return nil, fmt.Errorf("xpay: decode session response (http %d): %w", httpResp.StatusCode, err)
	}
	if httpResp.StatusCode < 200 || httpResp.StatusCode >= 300 {
		return nil, fmt.Errorf("xpay: session rejected (http %d): %.300s", httpResp.StatusCode, string(raw))
	}

	resp := &SessionResponse{Raw: decoded}
	resp.ID, _ = decoded["id"].(string)
	resp.ClientSecret, _ = decoded["clientSecret"].(string)
	resp.URL, _ = decoded["url"].(string)
	resp.Currency, _ = decoded["currency"].(string)
	resp.Status, _ = decoded["status"].(string)
	resp.PaymentStatus, _ = decoded["paymentStatus"].(string)
	if v, ok := decoded["amountTotal"].(float64); ok {
		resp.AmountTotal = int64(v)
	}
	if resp.ID == "" {
		return nil, fmt.Errorf("xpay: session response missing id: %.200s", string(raw))
	}
	// embedded sessions MUST hand back a clientSecret (the browser SDK
	// contract); hosted sessions MUST hand back a url (the WebView contract).
	if req.UIMode == "embedded" && resp.ClientSecret == "" {
		return nil, fmt.Errorf("xpay: embedded session missing clientSecret: %.200s", string(raw))
	}
	if req.UIMode == "hosted" && resp.URL == "" {
		return nil, fmt.Errorf("xpay: hosted session missing url: %.200s", string(raw))
	}
	return resp, nil
}

// ---------------------------------------------------------------------------
// Webhook signature verification (XPay-Signature: t=<unix>,v1=<hex>)
// ---------------------------------------------------------------------------

// ParseSignatureHeader splits "t=1730000000,v1=a1b2c3d4" into its parts.
// Both fields are required; anything malformed yields ok=false.
func ParseSignatureHeader(header string) (timestamp int64, v1 string, ok bool) {
	if header == "" {
		return 0, "", false
	}
	var tRaw string
	for _, part := range strings.Split(header, ",") {
		part = strings.TrimSpace(part)
		eq := strings.Index(part, "=")
		if eq <= 0 {
			continue
		}
		switch part[:eq] {
		case "t":
			tRaw = part[eq+1:]
		case "v1":
			v1 = part[eq+1:]
		}
	}
	if tRaw == "" || v1 == "" {
		return 0, "", false
	}
	ts, err := strconv.ParseInt(tRaw, 10, 64)
	if err != nil {
		return 0, "", false
	}
	return ts, v1, true
}

// VerifyWebhookSignature recomputes HMAC-SHA256(secret, "<t>.<rawBody>")
// over the RAW request bytes (never a re-serialization) and compares it,
// in constant time, with the v1 header value. The 5-minute replay window
// from the official docs is enforced here.
func VerifyWebhookSignature(rawBody []byte, header, secret string) bool {
	if header == "" || secret == "" || rawBody == nil {
		return false
	}
	ts, provided, ok := ParseSignatureHeader(header)
	if !ok {
		return false
	}
	if drift := time.Now().Unix() - ts; drift > signatureToleranceSeconds || drift < -signatureToleranceSeconds {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	// signedPayload = `${timestamp}.${rawRequestBody}` — timestamp rendered
	// as the SAME decimal string the header carried.
	mac.Write([]byte(strconv.FormatInt(ts, 10)))
	mac.Write([]byte("."))
	mac.Write(rawBody)
	expected := mac.Sum(nil)
	providedBytes, err := hex.DecodeString(provided)
	if err != nil {
		return false
	}
	return subtle.ConstantTimeCompare(expected, providedBytes) == 1
}
