// XPay online checkout (Phase X) — the replacement gateway branch + the
// verified webhook. Contract mirrors the Phase G Paymob path so billing
// semantics stay identical no matter which gateway is active:
//
//      (shared) POST /pharmacy/subscription/checkout — plan snapshot, pending
//               payments row (provider='xpay'), then THIS branch creates the
//               Checkout Session (api.xpay.app) and returns client_secret
//               (embedded web) or the hosted session url (mobile/legacy).
//               The browser/mobile result is UI-only.
//      POST /payments/webhook/xpay — HMAC-SHA256 verified (XPay-Signature:
//               t=…,v1=… over the RAW body) + optional URL token. The ONLY
//               activation path. Fulfil ONLY on paymentStatus == "paid" from
//               checkout.session.completed | checkout.session.async_payment_succeeded
//               (a completed session with "unpaid" is a Fawry-style reference
//               still pending — never fulfil, never fail). Idempotent by
//               construction: event.id is the dedup key, replays never
//               double-extend.
//
// Session anchoring: metadata.payment_id (set at creation) → fallback to
// payments.provider_reference (the session id). Amount tamper check:
// data.object.amount_total must equal the stored snapshot or the payment
// is failed, never activated.
package handlers

import (
        "encoding/json"
        "io"
        "log"
        "net/http"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/pharmacy-os/backend/internal/models"
        "github.com/pharmacy-os/backend/internal/xpay"
)

// createXPaySessionTx is the Phase X provider branch: session creation →
// honest ledger on failure → intent txn + reference binding → commit →
// response carrying everything the frontend/moble need.
func (h *Handler) createXPaySessionTx(c *gin.Context, s checkoutShared) {
        ctx, tx := s.ctx, s.tx
        client := xpay.New(h.config.XPAYSecretKey, h.config.XPAYPublishableKey, h.config.XPAYBaseURL)
        session, err := client.CreateCheckoutSession(ctx, xpay.SessionRequest{
                UIMode:          s.uiMode,
                AmountPiastres:  s.amount,
                Currency:        s.currency,
                PaymentID:       s.paymentID,
                RedirectURL:     s.redirectionURL,
                ItemName:        s.planName,
                ItemDescription: s.intervalLabel + " — " + s.planName,
                CustomerName:    s.companyName,
                CustomerEmail:   s.companyEmail,
                Locale:          s.locale,
        })
        if err != nil {
                // keep the ledger honest: record the failed intent attempt, then fail
                if _, _ = tx.Exec(ctx, `
                        INSERT INTO payment_transactions (payment_id, txn_type, hmac_verified, payload)
                        VALUES ($1, 'intent', FALSE, jsonb_build_object('error', $2::text))
                `, s.paymentID, err.Error()); err != nil {
                        log.Printf("[xpay] intent txn log failed payment=%s: %v", s.paymentID, err)
                }
                if _, _ = tx.Exec(ctx, `
                        UPDATE payments SET status = 'failed', updated_at = NOW() WHERE id = $1
                `, s.paymentID); err != nil {
                        log.Printf("[xpay] payment fail-mark failed payment=%s: %v", s.paymentID, err)
                }
                if commitErr := tx.Commit(ctx); commitErr != nil {
                        log.Printf("[xpay] commit after session failure failed: %v", commitErr)
                }
                log.Printf("[xpay] session creation failed payment=%s: %v", s.paymentID, err)
                c.JSON(http.StatusBadGateway, gin.H{
                        "error":   "xpay_session_failed",
                        "message": "تعذر بدء عملية الدفع — حاول مرة أخرى أو تواصل مع الدعم",
                })
                return
        }

        // intent audit row + reference binding (session id = provider_reference,
        // the webhook fallback anchor when metadata is absent)
        if _, err := tx.Exec(ctx, `
                INSERT INTO payment_transactions (payment_id, txn_type, provider_transaction_id, hmac_verified, payload)
                VALUES ($1, 'intent', $2, FALSE, $3::jsonb)
        `, s.paymentID, session.ID, rawJSON(session.Raw)); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "intent_txn_insert_failed", "detail": err.Error()})
                return
        }
        if _, err := tx.Exec(ctx, `
                UPDATE payments SET provider_reference = $2, updated_at = NOW() WHERE id = $1
        `, s.paymentID, session.ID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_reference_failed"})
                return
        }

        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "checkout_commit_failed"})
                return
        }

        log.Printf("[xpay] session created payment=%s session=%s ui=%s amount=%d", s.paymentID, session.ID, s.uiMode, s.amount)
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "payment_id":       s.paymentID,
                "amount_piastres":  s.amount,
                "currency":         s.currency,
                "billing_interval": s.billingInterval,
                "plan":             gin.H{"id": s.planID, "name": s.planName},
                "provider":         "xpay",
                // embedded (web): the SDK client secret + publishable key
                "client_secret": session.ClientSecret,
                "public_key":    h.config.XPAYPublishableKey,
                // hosted (mobile/legacy): the full-tab checkout URL
                "embed_url": session.URL,
                "status":    "pending",
        }})
}

// XPayWebhook is the ONLY activation path for XPay payments. It runs
// without session auth: the proof is the HMAC-SHA256 XPay-Signature over
// the RAW body (5-minute replay window) plus, when configured, the URL
// token. Idempotent: event.id dedup + succeeded-payment short-circuit.
func (h *Handler) XPayWebhook(c *gin.Context) {
        if h.config == nil || h.config.XPAYWebhookSecret == "" {
                c.JSON(http.StatusServiceUnavailable, gin.H{"error": "xpay_not_configured"})
                return
        }
        // provider-independent second check on the registered endpoint URL
        if h.config.XPAYWebhookToken != "" {
                provided := c.Query("token")
                if provided == "" || provided != h.config.XPAYWebhookToken {
                        log.Printf("[xpay] webhook rejected: bad url token from %s", c.ClientIP())
                        c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_webhook_token"})
                        return
                }
        }

        rawBody, err := io.ReadAll(io.LimitReader(c.Request.Body, 2<<20))
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "unreadable_body"})
                return
        }
        // Signature FIRST, over the raw bytes — parse only after the check.
        if !xpay.VerifyWebhookSignature(rawBody, c.GetHeader("XPay-Signature"), h.config.XPAYWebhookSecret) {
                log.Printf("[xpay] webhook rejected: signature verification failed (%d bytes from %s)",
                        len(rawBody), c.ClientIP())
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_signature"})
                return
        }

        var event struct {
                ID   string         `json:"id"`
                Type string         `json:"type"`
                Data struct {
                        Object map[string]any `json:"object"`
                } `json:"data"`
        }
        if err := json.Unmarshal(rawBody, &event); err != nil || event.ID == "" || event.Data.Object == nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_payload"})
                return
        }
        obj := event.Data.Object

        // Anchor the event to our payment row: metadata.payment_id (set at
        // session creation) is primary; the session id stored on
        // payments.provider_reference is the fallback.
        paymentID := nestedString(obj, "metadata", "payment_id")
        if paymentID == "" {
                sessionID, _ := obj["id"].(string)
                if sessionID != "" {
                        if err := h.db.QueryRow(c.Request.Context(), `
                                SELECT id::text FROM payments
                                WHERE provider = 'xpay' AND provider_reference = $1
                                ORDER BY created_at DESC LIMIT 1
                        `, sessionID).Scan(&paymentID); err != nil {
                                log.Printf("[xpay] webhook: no payment for session %s (event %s %s)", sessionID, event.Type, event.ID)
                                c.JSON(http.StatusBadRequest, gin.H{"error": "payment_not_found"})
                                return
                        }
                }
        }
        if paymentID == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "payment_reference_missing"})
                return
        }

        paymentStatus, _ := obj["paymentStatus"].(string)
        amountTotal := int64(0)
        if v, ok := obj["amountTotal"].(float64); ok {
                amountTotal = int64(v)
        }

        ctx := c.Request.Context()
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var companyID, planID, paymentStatusStored string
        var storedAmount int64
        err = tx.QueryRow(ctx, `
                SELECT company_id::text, plan_id::text, status, amount_piastres
                FROM payments WHERE id = $1 FOR UPDATE
        `, paymentID).Scan(&companyID, &planID, &paymentStatusStored, &storedAmount)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusBadRequest, gin.H{"error": "payment_not_found"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_lookup_failed"})
                return
        }

        // already delivered? — dedup on event.id: identical provider events on
        // the same payment are recorded once, replays change nothing.
        var exists bool
        if err := tx.QueryRow(ctx, `
                SELECT EXISTS(SELECT 1 FROM payment_transactions
                              WHERE payment_id = $1 AND provider_transaction_id = $2 AND txn_type = 'webhook')
        `, paymentID, event.ID).Scan(&exists); err == nil && exists {
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"received": true, "result": "duplicate_event"})
                return
        }

        record := func(verified bool) {
                insertWebhookTxn(ctx, tx, paymentID, event.ID, amountTotal, map[string]any{
                        "id": event.ID, "type": event.Type, "object": obj,
                }, verified)
        }

        switch {
        case (event.Type == "checkout.session.completed" || event.Type == "checkout.session.async_payment_succeeded") &&
                paymentStatus == "paid":
                // amount tamper check — the verified signature says one thing, our
                // snapshot another: never process, keep the audit row, fail the payment.
                if amountTotal != storedAmount {
                        log.Printf("[xpay] webhook AMOUNT MISMATCH payment=%s webhook=%d stored=%d — failing payment",
                                paymentID, amountTotal, storedAmount)
                        record(true)
                        _, _ = tx.Exec(ctx, `UPDATE payments SET status = 'failed', updated_at = NOW() WHERE id = $1`, paymentID)
                        _ = tx.Commit(ctx)
                        c.JSON(http.StatusOK, gin.H{"received": true, "result": "amount_mismatch_failed"})
                        return
                }

                // already processed? — idempotent replay: log the event, change nothing.
                if paymentStatusStored == models.PaymentStatusSucceeded {
                        record(true)
                        _ = tx.Commit(ctx)
                        c.JSON(http.StatusOK, gin.H{"received": true, "result": "already_processed"})
                        return
                }

                if _, err := applySucceededPaymentTx(ctx, tx, companyID, planID, paymentBillingInterval(ctx, tx, paymentID), paymentID); err != nil {
                        log.Printf("[xpay] webhook activation failed payment=%s: %v", paymentID, err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "activation_failed"})
                        return
                }
                if _, err := tx.Exec(ctx, `
                        UPDATE payments SET status = 'succeeded', updated_at = NOW() WHERE id = $1
                `, paymentID); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_update_failed"})
                        return
                }
                record(true)
                // Provider webhook has no tenant session: the hmac_verified row in
                // payment_transactions IS the immutable audit trail here.
                if err := tx.Commit(ctx); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "webhook_commit_failed"})
                        return
                }
                if h.subs != nil {
                        h.subs.Invalidate(companyID)
                }
                log.Printf("[xpay] webhook ACTIVATED payment=%s company=%s amount=%d event=%s",
                        paymentID, companyID, amountTotal, event.Type)
                c.JSON(http.StatusOK, gin.H{"received": true, "result": "activated"})

        case event.Type == "checkout.session.async_payment_failed" || event.Type == "checkout.session.expired":
                // definitive abandonment/decline — the modal's poll will see it and
                // let the customer retry. Only a pending payment flips; a succeeded
                // one never regresses.
                if err == nil && paymentStatusStored == models.PaymentStatusPending {
                        if _, err := tx.Exec(ctx, `
                                UPDATE payments SET status = 'failed', updated_at = NOW() WHERE id = $1
                        `, paymentID); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_update_failed"})
                                return
                        }
                }
                record(true)
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"received": true, "result": "recorded"})

        default:
                // charge.failed (customer may retry inside the same session — never
                // fails the payment), completed+unpaid (Fawry-style reference
                // pending — wait for async_payment_succeeded), and anything else:
                // record for the ledger, no state change.
                record(true)
                _ = tx.Commit(ctx)
                c.JSON(http.StatusOK, gin.H{"received": true, "result": "recorded"})
        }
}
