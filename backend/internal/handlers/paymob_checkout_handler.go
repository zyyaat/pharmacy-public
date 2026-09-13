// Paymob online checkout (Phase G) — the EMBEDDED flow the owner asked
// for: the card form renders INSIDE the pharmacy app's subscription modal
// (Unified Checkout iframe). The customer never navigates to a Paymob page
// and back; card data never touches our servers (PCI on Paymob's iframe).
//
//   POST /pharmacy/subscription/checkout   — create payment + intention,
//                                            return client_secret + embed URL
//   GET  /pharmacy/subscription/payments/:id — poll while the modal is open
//   POST /payments/webhook/paymob          — HMAC-verified activation
//                                            (the ONLY activation path)
//
// Checkout is deliberately NOT behind the plan permission/status gates: an
// expired or suspended company must be able to pay to recover — that is
// the entire point of the recovery flow. The mutation principal + CSRF
// guards still apply, and the company scope is resolved server-side.
package handlers

import (
        "context"
        "crypto/subtle"
        "encoding/json"
        "io"
        "log"
        "net/http"
        "net/url"
        "strconv"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
        "github.com/pharmacy-os/backend/internal/paymob"
)

// CreatePharmacyCheckout creates a pending payment + Paymob intention and
// returns everything the subscription modal needs to render the embedded
// checkout iframe: { payment_id, client_secret, public_key, embed_url }.
func (h *Handler) CreatePharmacyCheckout(c *gin.Context) {
        if h.config == nil || !h.config.PaymobEnabled() {
                c.JSON(http.StatusServiceUnavailable, gin.H{
                        "error":   "paymob_not_configured",
                        "message": "الدفع الإلكتروني غير مفعّل حالياً — تواصل مع الدعم أو استخدم الدفع اليدوي",
                })
                return
        }
        if h.subs == nil {
                c.JSON(http.StatusServiceUnavailable, gin.H{"error": "subscription_system_unavailable"})
                return
        }
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.ID == "" {
                c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication_required"})
                return
        }
        companyID := h.companyIDForGate(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_scope_unresolved"})
                return
        }

        var body struct {
                PlanID          string `json:"plan_id"`
                BillingInterval string `json:"billing_interval"`
        }
        if err := c.ShouldBindJSON(&body); err != nil || body.PlanID == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "plan_id و billing_interval مطلوبان"})
                return
        }
        if body.BillingInterval != models.BillingIntervalMonthly && body.BillingInterval != models.BillingIntervalYearly {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_interval", "message": "اختر فوترة شهرية أو سنوية"})
                return
        }

        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        // The plan must be live, public (self-serve) and priced — snapshot at
        // intention time protects against later plan edits (old invoices keep
        // their price).
        var planName, currency string
        var amount int64
        if err := tx.QueryRow(ctx, `
                SELECT name, currency,
                       CASE $2 WHEN 'yearly' THEN yearly_price_piastres ELSE monthly_price_piastres END
                FROM plans
                WHERE id = $1 AND is_active = TRUE AND is_public = TRUE AND deleted_at IS NULL
        `, body.PlanID, body.BillingInterval).Scan(&planName, &currency, &amount); err != nil {
                if err == pgx.ErrNoRows {
                        c.JSON(http.StatusNotFound, gin.H{"error": "plan_not_found", "message": "الخطة غير متاحة للاشتراك"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_lookup_failed"})
                return
        }
        if amount <= 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "plan_price_not_configured", "message": "سعر هذه الخطة غير مضبوط بعد"})
                return
        }

        // company snapshot for the intention billing_data
        var companyName, companyEmail string
        if err := tx.QueryRow(ctx, `
                SELECT name, COALESCE(email, '') FROM companies WHERE id = $1 AND deleted_at IS NULL
        `, companyID).Scan(&companyName, &companyEmail); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "company_lookup_failed"})
                return
        }

        var paymentID string
        if err := tx.QueryRow(ctx, `
                INSERT INTO payments (company_id, plan_id, billing_interval,
                                      amount_piastres, currency, provider, status, metadata)
                VALUES ($1, $2, $3, $4, $5, 'paymob', 'pending',
                        jsonb_build_object('initiated_by', $6::text, 'channel', 'embedded_checkout'))
                RETURNING id::text
        `, companyID, body.PlanID, body.BillingInterval, amount, currency,
                principal.Email).Scan(&paymentID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_insert_failed", "detail": err.Error()})
                return
        }

        intervalLabel := "اشتراك شهري"
        if body.BillingInterval == models.BillingIntervalYearly {
                intervalLabel = "اشتراك سنوي"
        }
        redirectionURL := ""
        if h.config.PublicAppURL != "" {
                redirectionURL = strings.TrimRight(h.config.PublicAppURL, "/") +
                        "/settings/subscription?payment=" + paymentID
        }

        client := paymob.New(h.config.PaymobSecretKey, h.config.PaymobPublicKey,
                h.config.PaymobCardIntegrationID, h.config.PaymobWalletIntegrationID,
                h.config.PaymobBaseURL)
        intention, err := client.CreateIntention(ctx, paymob.IntentionRequest{
                AmountPiastres:   amount,
                Currency:         currency,
                SpecialReference: paymentID,
                NotificationURL:  h.paymobWebhookURL(c),
                RedirectionURL:   redirectionURL,
                ItemName:         planName,
                ItemDescription:  intervalLabel + " — " + planName,
                BillingFirstName: companyName,
                BillingLastName:  "OS",
                BillingEmail:     companyEmail,
        })
        if err != nil {
                // keep the ledger honest: record the failed intent attempt, then fail
                if _, _ = tx.Exec(ctx, `
                        INSERT INTO payment_transactions (payment_id, txn_type, hmac_verified, payload)
                        VALUES ($1, 'intent', FALSE, jsonb_build_object('error', $2::text))
                `, paymentID, err.Error()); err != nil {
                        log.Printf("[paymob] intent txn log failed payment=%s: %v", paymentID, err)
                }
                if _, _ = tx.Exec(ctx, `
                        UPDATE payments SET status = 'failed', updated_at = NOW() WHERE id = $1
                `, paymentID); err != nil {
                        log.Printf("[paymob] payment fail-mark failed payment=%s: %v", paymentID, err)
                }
                if commitErr := tx.Commit(ctx); commitErr != nil {
                        log.Printf("[paymob] commit after intent failure failed: %v", commitErr)
                }
                log.Printf("[paymob] intention failed payment=%s: %v", paymentID, err)
                c.JSON(http.StatusBadGateway, gin.H{
                        "error":   "paymob_intention_failed",
                        "message": "تعذر بدء عملية الدفع — حاول مرة أخرى أو تواصل مع الدعم",
                })
                return
        }

        // intent audit row + reference binding
        if _, err := tx.Exec(ctx, `
                INSERT INTO payment_transactions (payment_id, txn_type, provider_transaction_id, hmac_verified, payload)
                VALUES ($1, 'intent', $2, FALSE, $3::jsonb)
        `, paymentID, intention.IntentionOrderID, rawJSON(intention.Raw)); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "intent_txn_insert_failed", "detail": err.Error()})
                return
        }
        if _, err := tx.Exec(ctx, `
                UPDATE payments SET provider_reference = $2, updated_at = NOW() WHERE id = $1
        `, paymentID, intention.IntentionOrderID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_reference_failed"})
                return
        }

        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "checkout_commit_failed"})
                return
        }

        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "payment_id":      paymentID,
                "amount_piastres": amount,
                "currency":        currency,
                "billing_interval": body.BillingInterval,
                "plan":            gin.H{"id": body.PlanID, "name": planName},
                "client_secret":   intention.ClientSecret,
                "public_key":      h.config.PaymobPublicKey,
                "embed_url":       client.EmbedURL(intention.ClientSecret),
                "status":          "pending",
        }})
}

// GetPharmacyPaymentStatus lets the open modal poll until the verified
// webhook flips the payment out of pending. Company-scoped so a payment id
// is only ever visible to its own company.
func (h *Handler) GetPharmacyPaymentStatus(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.ID == "" {
                c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication_required"})
                return
        }
        companyID := h.companyIDForGate(c, principal)
        if companyID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "company_scope_unresolved"})
                return
        }
        paymentID := c.Param("id")

        var status, planSlug, planName, currency string
        var amount int64
        var createdAt, updatedAt time.Time
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT p.status, p.amount_piastres, p.currency, pl.slug, pl.name,
                       p.created_at, p.updated_at
                FROM payments p
                JOIN plans pl ON pl.id = p.plan_id
                WHERE p.id = $1 AND p.company_id = $2
        `, paymentID, companyID).Scan(&status, &amount, &currency, &planSlug, &planName, &createdAt, &updatedAt)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusNotFound, gin.H{"error": "payment_not_found"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_status_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "id":               paymentID,
                "status":           status,
                "amount_piastres":  amount,
                "currency":         currency,
                "plan":             gin.H{"slug": planSlug, "name": planName},
                "created_at":       createdAt.UTC().Format(time.RFC3339),
                "updated_at":       updatedAt.UTC().Format(time.RFC3339),
        }})
}

// PaymobWebhook is the ONLY activation path for online payments. It runs
// without session auth: the proof is the HMAC-SHA512 signature over the
// documented field order plus (when configured) the URL token. Idempotent
// by construction: replayed or duplicate webhooks never double-extend.
func (h *Handler) PaymobWebhook(c *gin.Context) {
        if h.config == nil || h.config.PaymobHMACSecret == "" {
                c.JSON(http.StatusServiceUnavailable, gin.H{"error": "paymob_not_configured"})
                return
        }
        // provider-independent second check on the registered URL
        if h.config.PaymobWebhookToken != "" {
                provided := c.Query("token")
                if subtle.ConstantTimeCompare([]byte(provided), []byte(h.config.PaymobWebhookToken)) != 1 {
                        log.Printf("[paymob] webhook rejected: bad url token from %s", c.ClientIP())
                        c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_webhook_token"})
                        return
                }
        }

        rawBody, err := io.ReadAll(io.LimitReader(c.Request.Body, 2<<20))
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "unreadable_body"})
                return
        }
        var envelope struct {
                Type string         `json:"type"`
                Obj  map[string]any `json:"obj"`
        }
        if err := json.Unmarshal(rawBody, &envelope); err != nil || envelope.Obj == nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_payload"})
                return
        }
        obj := envelope.Obj

        providedHMAC, _ := obj["hmac"].(string)
        if !paymob.VerifyTransactionHMAC(obj, providedHMAC, h.config.PaymobHMACSecret) {
                log.Printf("[paymob] webhook rejected: HMAC verification failed (type=%s)", envelope.Type)
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_hmac"})
                return
        }

        // Anchor the transaction to our payment row: special_reference (set at
        // intention time) carries payments.id; fall back to the intention order
        // id stored on payments.provider_reference.
        paymentID := firstString(obj["special_reference"],
                nestedString(obj, "order", "merchant_order_id"),
                nestedString(obj, "order", "special_reference"))
        if paymentID == "" {
                if orderID := nestedNumber(obj, "order", "id"); orderID != 0 {
                        err := h.db.QueryRow(c.Request.Context(), `
                                SELECT id::text FROM payments
                                WHERE provider = 'paymob' AND provider_reference = $1
                                ORDER BY created_at DESC LIMIT 1
                        `, orderID).Scan(&paymentID)
                        if err != nil {
                                log.Printf("[paymob] webhook: no payment for order id %v", orderID)
                                c.JSON(http.StatusBadRequest, gin.H{"error": "payment_not_found"})
                                return
                        }
                }
        }
        if paymentID == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "payment_reference_missing"})
                return
        }

        providerTxnID := ""
        if id, ok := obj["id"].(float64); ok {
                providerTxnID = formatInt64(int64(id))
        }
        amountCents := int64(0)
        if v, ok := obj["amount_cents"].(float64); ok {
                amountCents = int64(v)
        }
        success, _ := obj["success"].(bool)
        pending, _ := obj["pending"].(bool)

        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var companyID, planID, paymentStatus string
        var storedAmount int64
        err = tx.QueryRow(ctx, `
                SELECT company_id::text, plan_id::text, status, amount_piastres
                FROM payments WHERE id = $1 FOR UPDATE
        `, paymentID).Scan(&companyID, &planID, &paymentStatus, &storedAmount)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusBadRequest, gin.H{"error": "payment_not_found"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_lookup_failed"})
                return
        }

        // amount tamper check — the verified signature says one thing, our
        // snapshot another: never process, keep the audit row, fail the payment.
        if amountCents != storedAmount {
                log.Printf("[paymob] webhook AMOUNT MISMATCH payment=%s webhook=%d stored=%d — failing payment", paymentID, amountCents, storedAmount)
                insertWebhookTxn(ctx, tx, paymentID, providerTxnID, amountCents, obj, true)
                _, _ = tx.Exec(ctx, `UPDATE payments SET status = 'failed', updated_at = NOW() WHERE id = $1`, paymentID)
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"received": true, "result": "amount_mismatch_failed"})
                return
        }

        // already processed? — idempotent replay: log the event, change nothing.
        if paymentStatus == models.PaymentStatusSucceeded && success {
                insertWebhookTxn(ctx, tx, paymentID, providerTxnID, amountCents, obj, true)
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"received": true, "result": "already_processed"})
                return
        }

        if success {
                subscriptionID, err := applySucceededPaymentTx(ctx, tx, companyID, planID, paymentBillingInterval(ctx, tx, paymentID), paymentID)
                if err != nil {
                        log.Printf("[paymob] webhook activation failed payment=%s: %v", paymentID, err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "activation_failed"})
                        return
                }
                _ = subscriptionID
                if _, err := tx.Exec(ctx, `
                        UPDATE payments SET status = 'succeeded', updated_at = NOW() WHERE id = $1
                `, paymentID); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_update_failed"})
                        return
                }
                insertWebhookTxn(ctx, tx, paymentID, providerTxnID, amountCents, obj, true)
                // Tenant audit (audit_logs) is pharmacy-scoped and session-bound — a
                // provider webhook has neither. The hmac_verified row in
                // payment_transactions IS the immutable audit trail here.
                if err := tx.Commit(ctx); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "webhook_commit_failed"})
                        return
                }
                if h.subs != nil {
                        h.subs.Invalidate(companyID)
                }
                log.Printf("[paymob] webhook ACTIVATED payment=%s company=%s amount=%d", paymentID, companyID, amountCents)
                c.JSON(http.StatusOK, gin.H{"received": true, "result": "activated"})
                return
        }

        insertWebhookTxn(ctx, tx, paymentID, providerTxnID, amountCents, obj, true)
        if !pending {
                // a definitive failure (declined card etc.) — the modal's poll will
                // see it and let the customer retry.
                if _, err := tx.Exec(ctx, `
                        UPDATE payments SET status = 'failed', updated_at = NOW() WHERE id = $1
                `, paymentID); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_update_failed"})
                        return
                }
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "webhook_commit_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"received": true, "result": "recorded"})
}

// paymobWebhookURL derives the public callback URL Paymob should POST to:
// the same host the checkout request reached (DockHosting terminates TLS
// and preserves Host / X-Forwarded-Proto), plus the URL token when one is
// configured. This URL is sent as notification_url on every intention —
// the dashboard-registered webhook is only a fallback.
func (h *Handler) paymobWebhookURL(c *gin.Context) string {
        scheme := "https"
        if proto := strings.TrimSpace(c.GetHeader("X-Forwarded-Proto")); proto != "" {
                scheme = proto
        } else if c.Request.TLS != nil {
                scheme = "https"
        }
        u := scheme + "://" + c.Request.Host + "/api/v1/payments/webhook/paymob"
        if h.config != nil && h.config.PaymobWebhookToken != "" {
                u += "?token=" + url.QueryEscape(h.config.PaymobWebhookToken)
        }
        return u
}

// paymentBillingInterval reads the interval off the payment row (the
// snapshot decides the extension length — never the webhook payload).
func paymentBillingInterval(ctx context.Context, tx pgx.Tx, paymentID string) string {
        var interval string
        _ = tx.QueryRow(ctx, `
                SELECT billing_interval FROM payments WHERE id = $1
        `, paymentID).Scan(&interval)
        return interval
}

func insertWebhookTxn(ctx context.Context, tx pgx.Tx, paymentID, providerTxnID string, amount int64, obj map[string]any, verified bool) {
        // duplicate provider events on the same payment are recorded once
        if providerTxnID != "" {
                var exists bool
                if err := tx.QueryRow(ctx, `
                        SELECT EXISTS(SELECT 1 FROM payment_transactions
                                      WHERE payment_id = $1 AND provider_transaction_id = $2 AND txn_type = 'webhook')
                `, paymentID, providerTxnID).Scan(&exists); err == nil && exists {
                        return
                }
        }
        payload, _ := json.Marshal(obj)
        if _, err := tx.Exec(ctx, `
                INSERT INTO payment_transactions
                    (payment_id, txn_type, provider_transaction_id, amount_piastres, hmac_verified, payload)
                VALUES ($1, 'webhook', NULLIF($2, ''), $3, $4, $5::jsonb)
        `, paymentID, providerTxnID, amount, verified, string(payload)); err != nil {
                log.Printf("[paymob] webhook txn insert failed payment=%s: %v", paymentID, err)
        }
}

func firstString(values ...any) string {
        for _, v := range values {
                if s, ok := v.(string); ok && s != "" {
                        return s
                }
        }
        return ""
}

func nestedString(obj map[string]any, parent, child string) string {
        if nested, ok := obj[parent].(map[string]any); ok {
                if s, ok := nested[child].(string); ok {
                        return s
                }
        }
        return ""
}

func nestedNumber(obj map[string]any, parent, child string) int64 {
        if nested, ok := obj[parent].(map[string]any); ok {
                if f, ok := nested[child].(float64); ok {
                        return int64(f)
                }
        }
        return 0
}

func formatInt64(v int64) string {
        return strconv.FormatInt(v, 10)
}

func rawJSON(m map[string]any) string {
        b, err := json.Marshal(m)
        if err != nil {
                return "{}"
        }
        return string(b)
}
