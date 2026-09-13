// Package paymob — server-side client for the Paymob Intention API
// (Unified Checkout / embedded Pixel flow, Phase G).
//
// Flow contract:
//
//      Backend   POST {base}/v1/intention/
//                Authorization: Token <Secret Key>       (server-only secret,
//                the dashboard field literally named "Secret Key")
//                payment_methods   = [<Integration ID>]  (body, NOT the URL)
//                amount            = integer piastres/cents (10000 = 100 EGP)
//                special_reference = <our payments.id>   (idempotency anchor)
//                notification_url  = <our webhook URL>   (drives the callback)
//                ← { client_secret, intention_order_id, ... }
//      Frontend  <iframe src="{base}/unifiedcheckout/?publicKey=<pk>&clientSecret=<cs>">
//                the card form lives INSIDE the pharmacy app page — the
//          customer never navigates away (PCI handled by Paymob).
//      Webhook   POST /api/v1/payments/webhook/paymob
//                HMAC-SHA512 verified server-side — the ONLY activation path.
//
// The frontend never proves a payment; it only renders state.
package paymob

import (
        "bytes"
        "context"
        "crypto/hmac"
        "crypto/sha512"
        "crypto/subtle"
        "encoding/hex"
        "encoding/json"
        "fmt"
        "io"
        "log"
        "net/http"
        "strconv"
        "strings"
        "time"
)

const defaultTimeout = 20 * time.Second

// Client is a thin Intention API client built from the environment config.
type Client struct {
        SecretKey           string // server-only secret — dashboard "Secret Key"
        PublicKey           string // pk_... — embedded in the iframe URL (safe for clients)
        CardIntegrationID   string
        WalletIntegrationID string // optional second channel
        BaseURL             string // e.g. https://accept.paymob.com
        HTTP                *http.Client
}

// New builds a client from the loaded config values.
func New(secretKey, publicKey, cardIntegrationID, walletIntegrationID, baseURL string) *Client {
        return &Client{
                SecretKey:           secretKey,
                PublicKey:           publicKey,
                CardIntegrationID:   cardIntegrationID,
                WalletIntegrationID: walletIntegrationID,
                BaseURL:             baseURL,
                HTTP:                &http.Client{Timeout: defaultTimeout},
        }
}

// IntentionRequest is the server-side payment intent we create per attempt.
type IntentionRequest struct {
        AmountPiastres   int64  // sent as-is: Paymob's "amount" is in cents = our piastres
        Currency         string // e.g. EGP
        SpecialReference string // our payments.id — echoes back in webhooks
        NotificationURL  string // our webhook endpoint — Paymob POSTs the result here
        RedirectionURL   string // where the checkout navigates after completion
        ItemName         string // plan display name
        ItemDescription  string // "اشتراك شهري — خطة X"
        BillingFirstName string
        BillingLastName  string
        BillingEmail     string
        BillingPhone     string
}

// IntentionResponse carries the fields we persist + the iframe contract.
type IntentionResponse struct {
        ClientSecret     string
        IntentionOrderID int64 // stored on payments.provider_reference
        Raw              map[string]any
}

// CreateIntention calls POST {base}/v1/intention/ (integration ID inside
// the body as payment_methods — see the package contract above).
func (c *Client) CreateIntention(ctx context.Context, req IntentionRequest) (*IntentionResponse, error) {
        if c.SecretKey == "" || c.CardIntegrationID == "" {
                return nil, fmt.Errorf("paymob: missing secret key or card integration ID")
        }

        channels := []int{}
        if c.CardIntegrationID != "" {
                if id, err := strconv.Atoi(c.CardIntegrationID); err == nil {
                        channels = append(channels, id)
                }
        }
        if c.WalletIntegrationID != "" {
                if id, err := strconv.Atoi(c.WalletIntegrationID); err == nil {
                        channels = append(channels, id)
                }
        }
        if len(channels) == 0 {
                return nil, fmt.Errorf("paymob: no valid integration IDs configured")
        }

        firstName := req.BillingFirstName
        if firstName == "" {
                firstName = "Pharmacy"
        }
        lastName := req.BillingLastName
        if lastName == "" {
                lastName = "OS"
        }
        email := req.BillingEmail
        if email == "" {
                email = "billing@pharmacy-os.local"
        }
        phone := req.BillingPhone
        if phone == "" {
                phone = "+201000000000"
        }

        // billing_data fields are mandatory on the intention API; they are
        // descriptive metadata only — the card is charged inside the iframe.
        body := map[string]any{
                "amount":            req.AmountPiastres,
                "currency":          req.Currency,
                "payment_methods":   channels,
                "special_reference": req.SpecialReference,
                "items": []map[string]any{{
                        "name":        req.ItemName,
                        "amount":      req.AmountPiastres,
                        "description": req.ItemDescription,
                        "quantity":    1,
                }},
                "billing_data": map[string]any{
                        "first_name":      firstName,
                        "last_name":       lastName,
                        "email":           email,
                        "phone_number":    phone,
                        "apartment":       "NA",
                        "floor":           "NA",
                        "street":          "NA",
                        "building":        "NA",
                        "shipping_method": "NA",
                        "postal_code":     "NA",
                        "city":            "Cairo",
                        "country":         "EGY", // 3-letter ISO per intention API docs
                        "state":           "Cairo",
                },
        }
        if req.RedirectionURL != "" {
                body["redirection_url"] = req.RedirectionURL
        }
        if req.NotificationURL != "" {
                body["notification_url"] = req.NotificationURL
        }

        url := c.BaseURL + "/v1/intention/"
        send := func(channels []int) (*IntentionResponse, error) {
                body["payment_methods"] = channels
                payload, err := json.Marshal(body)
                if err != nil {
                        return nil, fmt.Errorf("paymob: marshal intention: %w", err)
                }
                httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
                if err != nil {
                        return nil, fmt.Errorf("paymob: build request: %w", err)
                }
                httpReq.Header.Set("Content-Type", "application/json")
                httpReq.Header.Set("Authorization", "Token "+c.SecretKey)

                httpResp, err := c.HTTP.Do(httpReq)
                if err != nil {
                        return nil, fmt.Errorf("paymob: intention call failed: %w", err)
                }
                defer httpResp.Body.Close()
                raw, err := io.ReadAll(io.LimitReader(httpResp.Body, 1<<20))
                if err != nil {
                        return nil, fmt.Errorf("paymob: read intention response: %w", err)
                }

                var decoded map[string]any
                if err := json.Unmarshal(raw, &decoded); err != nil {
                        return nil, fmt.Errorf("paymob: decode intention response (http %d): %w", httpResp.StatusCode, err)
                }
                if httpResp.StatusCode < 200 || httpResp.StatusCode >= 300 {
                        return nil, fmt.Errorf("paymob: intention rejected (http %d): %.300s", httpResp.StatusCode, string(raw))
                }

                clientSecret, _ := decoded["client_secret"].(string)
                if clientSecret == "" {
                        return nil, fmt.Errorf("paymob: intention response missing client_secret: %.200s", string(raw))
                }
                resp := &IntentionResponse{ClientSecret: clientSecret, Raw: decoded}
                if id, ok := decoded["intention_order_id"].(float64); ok {
                        resp.IntentionOrderID = int64(id)
                }
                return resp, nil
        }

        resp, err := send(channels)
        if err != nil && strings.Contains(err.Error(), "(http 404)") && len(channels) > 1 {
                // ONE bad optional channel ID fails the whole intention with
                // "Integration ID does not exist" (Paymob validates every
                // payment_methods entry). Retry once with the card channel
                // alone so a stale wallet ID can never block payments.
                log.Printf("[paymob] intention 404 with %d channels — retrying with card channel only", len(channels))
                resp, err = send(channels[:1])
        }
        if err != nil {
                return nil, err
        }
        return resp, nil
}

// EmbedURL builds the Unified Checkout iframe src — the form rendered
// INSIDE the pharmacy app's subscription modal.
func (c *Client) EmbedURL(clientSecret string) string {
        return c.BaseURL + "/unifiedcheckout/?publicKey=" + c.PublicKey +
                "&clientSecret=" + clientSecret
}

// ---------------------------------------------------------------------------
// Webhook HMAC verification
// ---------------------------------------------------------------------------

// hmacFieldOrder is Paymob's documented ordered concatenation for the
// transaction callback signature (HMAC-SHA512, hex, lowercase). Dotted
// keys are nested ("order.id" → obj["order"]["id"]).
var hmacFieldOrder = []string{
        "amount_cents", "created_at", "currency", "error_occured",
        "has_parent_transaction", "id", "integration_id", "is_3d_secure",
        "is_auth", "is_capture", "is_refunded", "is_standalone_payment",
        "is_voided", "order.id", "owner", "pending",
        "source_data.pan", "source_data.sub_type", "source_data.type",
        "success",
}

// hmacValue renders one payload value the way Paymob concatenates it:
// booleans as true/false, numbers without scientific notation, missing or
// null as the empty string.
func hmacValue(v any) string {
        switch t := v.(type) {
        case nil:
                return ""
        case bool:
                if t {
                        return "true"
                }
                return "false"
        case float64:
                if t == float64(int64(t)) {
                        return strconv.FormatInt(int64(t), 10)
                }
                return strconv.FormatFloat(t, 'f', -1, 64)
        case string:
                return t
        default:
                return fmt.Sprintf("%v", t)
        }
}

func hmacLookup(obj map[string]any, dotted string) any {
        if v, ok := obj[dotted]; ok {
                return v
        }
        // nested lookup for the dotted families in the documented order
        var parent, child string
        for i := 0; i < len(dotted); i++ {
                if dotted[i] == '.' {
                        parent, child = dotted[:i], dotted[i+1:]
                }
        }
        if parent == "" {
                return nil
        }
        nested, ok := obj[parent].(map[string]any)
        if !ok {
                return nil
        }
        return nested[child]
}

// VerifyTransactionHMAC recomputes the signature over the documented field
// order and compares it (constant-time) with the provided hex digest.
func VerifyTransactionHMAC(obj map[string]any, providedHMAC, secret string) bool {
        if providedHMAC == "" || secret == "" || obj == nil {
                return false
        }
        concat := make([]byte, 0, 256)
        for _, field := range hmacFieldOrder {
                concat = append(concat, hmacValue(hmacLookup(obj, field))...)
        }
        mac := hmac.New(sha512.New, []byte(secret))
        mac.Write(concat)
        expected := mac.Sum(nil)
        provided, err := hex.DecodeString(providedHMAC)
        if err != nil {
                return false
        }
        return subtle.ConstantTimeCompare(expected, provided) == 1
}
