// Paymob diagnostics (Task 90 prod) — super-admin-only self-service answer
// to the intention 404 "Integration ID does not exist" investigation.
//
//   GET /api/v1/platform-admin/payments/paymob-diagnostics
//
// It echoes the EXACT Paymob configuration in use (base URL, masked secret
// keys, the literal integration ID values) and — when PAYMOB_DIAG_API_KEY
// is set in the hosting environment — probes Paymob's legacy API to list
// every integration ID that really exists on that account, then flags
// whether the configured card ID is among them. That turns the dashboard
// debate into a machine answer: either the configured ID is on the list
// (then the Secret Key belongs to a different account) or it is not (then
// the configured value itself is wrong / from another mode).
//
// Access is the platform-admin session (same guard as the rest of
// /platform-admin); the read-only GET needs no CSRF. Integration IDs are
// account configuration, not secret credentials; Secret/HMAC keys are only
// ever echoed masked.
package handlers

import (
        "os"
        "strconv"
        "strings"

        "github.com/gin-gonic/gin"
        "github.com/pharmacy-os/backend/internal/paymob"
)

func (h *Handler) PaymobDiagnostics(c *gin.Context) {
        cfg := h.config
        if cfg == nil {
                c.JSON(503, gin.H{"error": "config_unavailable"})
                return
        }

        resp := gin.H{
                "api_level":       APILevel,
                "paymob_enabled":  cfg.PaymobEnabled(),
                "active_gateway":  cfg.ActiveGateway(), // Phase X: "xpay" replaces paymob when configured
                "base_url":        cfg.PaymobBaseURL,
                "webhook_derived": "/api/v1/payments/webhook/paymob?token=<configured>",
                "xpay": gin.H{
                        // Phase X replacement-gateway subset — same masking rules
                        "enabled":        cfg.XPayEnabled(),
                        "base_url":       cfg.XPAYBaseURL,
                        "webhook_path":   "/api/v1/payments/webhook/xpay?token=<configured>",
                        "secret_key":     gin.H{"present": cfg.XPAYSecretKey != "", "hint": maskConfigSecret(cfg.XPAYSecretKey)},
                        "publishable_key": gin.H{"present": cfg.XPAYPublishableKey != "", "hint": maskConfigSecret(cfg.XPAYPublishableKey)},
                        "webhook_secret": gin.H{"present": cfg.XPAYWebhookSecret != "", "hint": maskConfigSecret(cfg.XPAYWebhookSecret)},
                        "webhook_token_present": cfg.XPAYWebhookToken != "",
                },
                "config": gin.H{
                        // masked — enough to compare first/last chars with the
                        // dashboard without ever exposing the credential
                        "secret_key": gin.H{"present": cfg.PaymobSecretKey != "", "hint": maskConfigSecret(cfg.PaymobSecretKey)},
                        "public_key": gin.H{"present": cfg.PaymobPublicKey != "", "hint": maskConfigSecret(cfg.PaymobPublicKey)},
                        // full value on purpose: the whole point is comparing it with
                        // the dashboard's Payment Integrations table
                        "card_integration_id":   integrationIDState(cfg.PaymobCardIntegrationID),
                        "wallet_integration_id": integrationIDState(cfg.PaymobWalletIntegrationID),
                        "hmac_secret":           gin.H{"present": cfg.PaymobHMACSecret != "", "hint": maskConfigSecret(cfg.PaymobHMACSecret)},
                        "webhook_token_present": cfg.PaymobWebhookToken != "",
                },
        }

        diagKey := strings.TrimSpace(os.Getenv("PAYMOB_DIAG_API_KEY"))
        if diagKey == "" {
                resp["account_probe"] = gin.H{
                        "skipped": true,
                        "how_to_enable": "Set PAYMOB_DIAG_API_KEY in the hosting environment to the API Key " +
                                "from the SAME Paymob dashboard account as the Secret Key (Developers → API Keys), " +
                                "rebuild, then reopen this page. It will list every integration ID that really " +
                                "exists on that account. Do NOT put the API Key into PAYMOB_API_KEY — that name " +
                                "is treated as a legacy alias of the Secret Key.",
                }
        } else {
                client := paymob.New(cfg.PaymobSecretKey, cfg.PaymobPublicKey,
                        cfg.PaymobCardIntegrationID, cfg.PaymobWalletIntegrationID, cfg.PaymobBaseURL)
                probe, err := client.ProbeAccountIntegrations(c.Request.Context(), diagKey)
                if err != nil {
                        resp["account_probe"] = gin.H{"ok": false, "error": err.Error()}
                } else {
                        existing := collectProbeIntegrationIDs(probe["integrations"])
                        cardFound, cardIsInt := lookupID(existing, cfg.PaymobCardIntegrationID)
                        walletFound, walletIsInt := lookupID(existing, cfg.PaymobWalletIntegrationID)
                        probeResp := gin.H{
                                "ok":           true,
                                "path":         probe["path"],
                                "integrations": probe["integrations"],
                        }
                        if cardIsInt {
                                probeResp["card_integration_id_found"] = cardFound
                        }
                        if walletIsInt {
                                probeResp["wallet_integration_id_found"] = walletFound
                        }
                        resp["account_probe"] = probeResp
                }
        }

        c.JSON(200, resp)
}

// maskConfigSecret keeps enough characters to eyeball a value against the
// dashboard without exposing usable credentials in the response body.
func maskConfigSecret(s string) string {
        s = strings.TrimSpace(s)
        if s == "" {
                return ""
        }
        if len(s) <= 8 {
                return "****"
        }
        return s[:4] + "…" + s[len(s)-4:]
}

func integrationIDState(v string) gin.H {
        v = strings.TrimSpace(v)
        if v == "" {
                return gin.H{"configured": false}
        }
        _, err := strconv.Atoi(v)
        return gin.H{"configured": true, "value": v, "is_integer": err == nil}
}

// collectProbeIntegrationIDs defensively extracts numeric IDs from the
// decoded legacy integrations list (array of objects with an "id" field —
// number or numeric string depending on the endpoint generation).
func collectProbeIntegrationIDs(v any) map[int64]bool {
        ids := map[int64]bool{}
        arr, ok := v.([]any)
        if !ok {
                return ids
        }
        for _, item := range arr {
                obj, ok := item.(map[string]any)
                if !ok {
                        continue
                }
                switch t := obj["id"].(type) {
                case float64:
                        ids[int64(t)] = true
                case string:
                        if n, err := strconv.ParseInt(strings.TrimSpace(t), 10, 64); err == nil {
                                ids[n] = true
                        }
                }
        }
        return ids
}

func lookupID(existing map[int64]bool, configured string) (found, isInt bool) {
        configured = strings.TrimSpace(configured)
        if configured == "" {
                return false, false
        }
        n, err := strconv.ParseInt(configured, 10, 64)
        if err != nil {
                return false, false
        }
        return existing[n], true
}
