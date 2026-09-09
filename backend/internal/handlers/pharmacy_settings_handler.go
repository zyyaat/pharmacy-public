package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// receiptSettings is the pharmacy-level configuration of the POS invoice
// receipt: paper geometry, print behaviour, and the optional header/footer
// content. It is stored under the "receipt" key of pharmacies.settings so
// every cashier device of the same pharmacy shares one configuration.
type receiptSettings struct {
	PaperWidthMM      int    `json:"paper_width_mm"`
	PrintMode         string `json:"print_mode"` // "auto" | "manual"
	Copies            int    `json:"copies"`
	ShowPhone         bool   `json:"show_phone"`
	ShowAddress       bool   `json:"show_address"`
	ShowCashier       bool   `json:"show_cashier"`
	ShowThankYou      bool   `json:"show_thank_you"`
	ThankYouText      string `json:"thank_you_text"`
	ShowReturnPolicy  bool   `json:"show_return_policy"`
	ReturnPolicyText  string `json:"return_policy_text"`
}

func defaultReceiptSettings() receiptSettings {
	return receiptSettings{
		PaperWidthMM:     80,
		PrintMode:        "auto",
		Copies:           1,
		ShowPhone:        true,
		ShowAddress:      true,
		ShowCashier:      true,
		ShowThankYou:     true,
		ThankYouText:     "شكراً لثقتكم — صحتك أمانة عندنا",
		ShowReturnPolicy: true,
		ReturnPolicyText: "الاسترجاع خلال 14 يوماً بالإيصال الأصلي",
	}
}

// normalize validates client-supplied values against the allowed envelope and
// fills everything missing from the defaults, so the stored document is
// always complete and safe to render on any device.
func (r receiptSettings) normalize(base receiptSettings) (receiptSettings, string) {
	out := base

	switch r.PaperWidthMM {
	case 58, 80:
		out.PaperWidthMM = r.PaperWidthMM
	case 0:
		// keep base
	default:
		return out, "عرض الورق يجب أن يكون 58 أو 80 ملم"
	}

	switch r.PrintMode {
	case "auto", "manual":
		out.PrintMode = r.PrintMode
	case "":
		// keep base
	default:
		return out, "وضع الطباعة يجب أن يكون تلقائي أو يدوي"
	}

	switch r.Copies {
	case 1, 2:
		out.Copies = r.Copies
	case 0:
		// keep base
	default:
		return out, "عدد النسخ يجب أن يكون 1 أو 2"
	}

	// Booleans: the zero value of a missing field is false, which is also a
	// legitimate choice, so they are taken as-is from the payload.

	const maxThankYou = 120
	const maxPolicy = 160
	if runeLen(r.ThankYouText) > maxThankYou {
		return out, "رسالة الشكر أطول من الحد المسموح (120 حرفاً)"
	}
	if runeLen(r.ReturnPolicyText) > maxPolicy {
		return out, "سياسة الاسترجاع أطول من الحد المسموح (160 حرفاً)"
	}
	out.ThankYouText = trimSpaceArabic(r.ThankYouText)
	out.ReturnPolicyText = trimSpaceArabic(r.ReturnPolicyText)
	return out, ""
}

func runeLen(s string) int { return len([]rune(s)) }

func trimSpaceArabic(s string) string {
	start, end := 0, len(s)
	for start < end && isSpaceRune(rune(s[start])) {
		start += len(string(rune(s[start])))
	}
	for end > start {
		r, size := lastRune(s[:end])
		if !isSpaceRune(r) {
			break
		}
		end -= size
	}
	return s[start:end]
}

func lastRune(s string) (rune, int) {
	for i := len(s) - 1; i >= 0; i-- {
		if (s[i] & 0xC0) != 0x80 {
			return rune(s[i]), len(s) - i
		}
	}
	return rune(s[0]), 1
}

func isSpaceRune(r rune) bool {
	return r == ' ' || r == '\t' || r == '\n' || r == '\r' || r == ' ' || r == '‏' || r == '‎'
}

// readReceiptDoc loads pharmacies.settings for the session pharmacy.
func (h *Handler) readReceiptDoc(ctx context.Context, pharmacyID string) (map[string]any, bool, error) {
	var raw []byte
	err := h.db.QueryRow(ctx,
		`SELECT settings FROM pharmacies WHERE id = $1 AND is_active = true`,
		pharmacyID,
	).Scan(&raw)
	if err != nil {
		return nil, false, err
	}
	doc := map[string]any{}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &doc); err != nil {
			// A corrupt document must never take the POS down: start fresh
			// and the next save rewrites the receipt namespace.
			return map[string]any{}, true, nil
		}
	}
	return doc, true, nil
}

// GetPharmacySettings returns the receipt configuration merged over code
// defaults, so the frontend always receives a complete object.
func (h *Handler) GetPharmacySettings(c *gin.Context) {
	principal, ok := pharmacyPrincipal(c)
	if !ok {
		return
	}
	doc, found, err := h.readReceiptDoc(c.Request.Context(), principal.PharmacyID)
	if err != nil || !found {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "settings_query_failed",
			"message": "تعذر تحميل إعدادات الصيدلية",
		})
		return
	}

	settings := defaultReceiptSettings()
	if section, ok := doc["receipt"]; ok {
		if payload, err := json.Marshal(section); err == nil {
			var stored receiptSettings
			if json.Unmarshal(payload, &stored) == nil {
				merged, _ := stored.normalize(settings)
				settings = merged
			}
		}
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"receipt": settings}})
}

// UpdatePharmacySettings replaces the "receipt" namespace of the pharmacy
// settings document. Unknown sibling namespaces are preserved untouched.
func (h *Handler) UpdatePharmacySettings(c *gin.Context) {
	principal, ok := pharmacyPrincipal(c)
	if !ok {
		return
	}

	var payload struct {
		Receipt *receiptSettings `json:"receipt"`
	}
	if err := c.ShouldBindJSON(&payload); err != nil || payload.Receipt == nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_settings_payload",
			"message": "صيغة الإعدادات غير صحيحة",
		})
		return
	}

	doc, found, err := h.readReceiptDoc(c.Request.Context(), principal.PharmacyID)
	if err != nil || !found {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "settings_query_failed",
			"message": "تعذر تحميل إعدادات الصيدلية",
		})
		return
	}

	current := defaultReceiptSettings()
	if section, ok := doc["receipt"]; ok {
		if existing, err := json.Marshal(section); err == nil {
			var stored receiptSettings
			if json.Unmarshal(existing, &stored) == nil {
				merged, _ := stored.normalize(current)
				current = merged
			}
		}
	}

	normalized, validationMessage := payload.Receipt.normalize(current)
	if validationMessage != "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_receipt_settings",
			"message": validationMessage,
		})
		return
	}

	doc["receipt"] = normalized
	blob, err := json.Marshal(doc)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "settings_encode_failed", "message": "تعذر حفظ الإعدادات"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	if _, err := h.db.Exec(ctx,
		`UPDATE pharmacies SET settings = $2::jsonb, updated_at = NOW() WHERE id = $1 AND is_active = true`,
		principal.PharmacyID, string(blob),
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "settings_update_failed",
			"message": "تعذر حفظ إعدادات الصيدلية",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{"receipt": normalized}})
}
