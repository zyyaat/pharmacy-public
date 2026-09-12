package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"sort"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/pharmacy-os/backend/internal/auth"
)

// Label template system (barcode system v1 — Final Decisions 7/9/13).
//
// Templates live in pharmacies.settings JSONB under the "labels" namespace,
// following the proven receiptSettings pattern: code defaults + a normalize
// function that rejects anything outside the envelope, so every device of
// the pharmacy renders the same configuration.
//
// Only CUSTOM templates are persisted. System templates are rebuilt from the
// code registry on every read, which means shipping a new system template in
// a release needs no data migration and stored data cannot drift from the
// registry (sizes, field vocabulary, quiet-zone rules).

// labelSize is one entry of the global size registry (mm). The registry is
// defined centrally (Final Decision 7): the two requested formats plus the
// market-recommended additions from the design report §7.4.
type labelSize struct {
	ID       string `json:"id"`
	WidthMM  int    `json:"width_mm"`
	HeightMM int    `json:"height_mm"`
	Name     string `json:"name"`
}

var labelSizes = []labelSize{
	{ID: "35x15", WidthMM: 35, HeightMM: 15, Name: "35×15 — باركود وسعر"},
	{ID: "35x25", WidthMM: 35, HeightMM: 25, Name: "35×25 — شريط الرف"},
	{ID: "50x25", WidthMM: 50, HeightMM: 25, Name: "50×25 — ملصق أوسع"},
	{ID: "58x30", WidthMM: 58, HeightMM: 30, Name: "58×30 — لفة حرارية"},
}

// allowedLabelFields is the renderable field vocabulary. The barcode field
// always renders the actual EAN-13 bars; everything else is text.
var allowedLabelFields = map[string]bool{
	"name":          true,
	"generic_name":  true,
	"strength":      true,
	"price":         true,
	"barcode":       true,
	"pharmacy_name": true,
	"units_hint":    true,
}

func isKnownLabelSize(id string) bool {
	for _, s := range labelSizes {
		if s.ID == id {
			return true
		}
	}
	return false
}

// labelTemplate describes one printable label layout. A template MUST
// include the "barcode" field — a label without the code is pointless.
type labelTemplate struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	System       bool     `json:"system"`
	SizeID       string   `json:"size_id"`
	Fields       []string `json:"fields"`
	FontScale    int      `json:"font_scale"` // percent, 70..200
	ShowPharmacy bool     `json:"show_pharmacy"`
}

// systemLabelTemplates is the built-in catalog (not storable, not deletable).
// Field order is the print order top-to-bottom.
func systemLabelTemplates() []labelTemplate {
	return []labelTemplate{
		{ID: "sys_35x15_barcode_price_name", Name: "ملصق بيع — باركود وسعر واسم", System: true,
			SizeID: "35x15", Fields: []string{"barcode", "price", "name"}, FontScale: 100},
		{ID: "sys_35x15_barcode_name", Name: "ملصق بيع — باركود واسم", System: true,
			SizeID: "35x15", Fields: []string{"barcode", "name"}, FontScale: 100},
		{ID: "sys_35x25_name_price_barcode", Name: "شريط رف — اسم وسعر وباركود", System: true,
			SizeID: "35x25", Fields: []string{"name", "price", "barcode"}, FontScale: 100},
		{ID: "sys_50x25_full", Name: "ملصق أوسع — الاسم والتركيز والسعر والباركود", System: true,
			SizeID: "50x25", Fields: []string{"name", "strength", "price", "barcode"}, FontScale: 100},
		{ID: "sys_58x30_thermal", Name: "لفة حرارية — ملصق كامل", System: true,
			SizeID: "58x30", Fields: []string{"name", "price", "barcode"}, FontScale: 110},
	}
}

// labelSettings is the persisted shape. Customs only — system templates are
// merged at read time from the registry.
type labelSettings struct {
	DefaultTemplateID string          `json:"default_template_id"`
	Templates         []labelTemplate `json:"templates"`
}

func defaultLabelSettings() labelSettings {
	return labelSettings{
		DefaultTemplateID: systemLabelTemplates()[0].ID,
		Templates:         []labelTemplate{},
	}
}

const maxLabelTemplates = 50

// normalizeLabelSettings validates a client payload against the envelope and
// fills missing pieces from the base. System IDs in the incoming list are
// ignored (the registry owns them); entries without an ID get one assigned,
// which is how "حفظ باسم" materialises a new named template.
func normalizeLabelSettings(incoming, base labelSettings) (labelSettings, string) {
	out := base

	if incoming.DefaultTemplateID != "" {
		out.DefaultTemplateID = incoming.DefaultTemplateID
	}
	if incoming.Templates != nil {
		out.Templates = make([]labelTemplate, 0, len(incoming.Templates))
		seen := map[string]bool{}
		for _, tpl := range incoming.Templates {
			if len(out.Templates) >= maxLabelTemplates {
				return out, "عدد القوالب المخصصة تجاوز الحد المسموح (50 قالبًا)"
			}
			if tpl.System {
				continue // registry-owned values are never stored
			}
			name := trimSpaceArabic(tpl.Name)
			if name == "" {
				return out, "اسم القالب مطلوب"
			}
			if runeLen(name) > 60 {
				return out, "اسم القالب أطول من الحد المسموح (60 حرفًا)"
			}
			if !isKnownLabelSize(tpl.SizeID) {
				return out, "مقاس الملصق غير معروف"
			}
			if len(tpl.Fields) == 0 || len(tpl.Fields) > 4 {
				return out, "يجب اختيار من حقل إلى أربعة حقول للقالب"
			}
			fields := make([]string, 0, len(tpl.Fields))
			hasBarcode := false
			for _, f := range tpl.Fields {
				if !allowedLabelFields[f] {
					return out, "حقل غير معروف في القالب: " + f
				}
				if f == "barcode" {
					hasBarcode = true
				}
				fields = append(fields, f)
			}
			if !hasBarcode {
				return out, "قالب الملصق يجب أن يحتوي على حقل الباركود"
			}
			scale := tpl.FontScale
			if scale == 0 {
				scale = 100
			}
			if scale < 70 || scale > 200 {
				return out, "حجم الخط يجب أن يكون بين 70% و200%"
			}
			id := trimSpaceArabic(tpl.ID)
			if id == "" {
				id = newLabelTemplateID()
			}
			if seen[id] {
				return out, "يوجد قالبان بنفس المعرّف: " + id
			}
			seen[id] = true
			out.Templates = append(out.Templates, labelTemplate{
				ID: id, Name: name, System: false, SizeID: tpl.SizeID,
				Fields: fields, FontScale: scale, ShowPharmacy: tpl.ShowPharmacy,
			})
		}
	}

	// The default must point at a template that will exist after the merge
	// (system or custom); otherwise fall back to the first system template
	// so the print button never dangles.
	if !labelTemplateExists(out, out.DefaultTemplateID) {
		out.DefaultTemplateID = systemLabelTemplates()[0].ID
	}
	return out, ""
}

func labelTemplateExists(s labelSettings, id string) bool {
	if id == "" {
		return false
	}
	for _, t := range systemLabelTemplates() {
		if t.ID == id {
			return true
		}
	}
	for _, t := range s.Templates {
		if t.ID == id {
			return true
		}
	}
	return false
}

// newLabelTemplateID mints a collision-safe id for a named template.
func newLabelTemplateID() string {
	buf := make([]byte, 6)
	if _, err := rand.Read(buf); err != nil {
		return "lbl_" + time.Now().UTC().Format("20060102150405")
	}
	return "lbl_" + hex.EncodeToString(buf)
}

// readLabelSettings loads the merged view: registry system templates first
// (stable order), then customs. Corrupt documents degrade to defaults
// instead of breaking the settings page (same stance as receipts).
func (h *Handler) readLabelSettings(ctx context.Context, pharmacyID string) (labelSettings, bool, error) {
	doc, found, err := h.readReceiptDoc(ctx, pharmacyID)
	if err != nil || !found {
		return defaultLabelSettings(), found, err
	}
	stored := defaultLabelSettings()
	if section, ok := doc["labels"]; ok {
		if payload, err := json.Marshal(section); err == nil {
			var parsed labelSettings
			if json.Unmarshal(payload, &parsed) == nil {
				stored = parsed
				if stored.Templates == nil {
					stored.Templates = []labelTemplate{}
				}
			}
		}
	}
	return stored, true, nil
}

// GetLabelSettings returns the full render kit for the settings panel:
// sizes registry, allowed fields, system templates and stored customs.
// GET /pharmacy/settings/labels
func (h *Handler) GetLabelSettings(c *gin.Context) {
	principal, ok := pharmacyPrincipal(c)
	if !ok {
		return
	}
	stored, found, err := h.readLabelSettings(c.Request.Context(), principal.PharmacyID)
	if err != nil || !found {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "settings_query_failed",
			"message": "تعذر تحميل إعدادات الملصقات",
		})
		return
	}

	templates := append([]labelTemplate{}, systemLabelTemplates()...)
	templates = append(templates, stored.Templates...)
	sort.SliceStable(templates, func(i, j int) bool { return templates[i].ID < templates[j].ID })

	sizes := make([]labelSize, len(labelSizes))
	copy(sizes, labelSizes)

	fields := make([]string, 0, len(allowedLabelFields))
	for f := range allowedLabelFields {
		fields = append(fields, f)
	}
	sort.Strings(fields)

	c.JSON(http.StatusOK, gin.H{"data": gin.H{
		"default_template_id": stored.DefaultTemplateID,
		"templates":           templates,
		"sizes":               sizes,
		"fields":              fields,
	}})
}

// UpdateLabelSettings replaces the custom templates list and the default
// template of the "labels" namespace. Sibling namespaces (receipt, ...) are
// preserved untouched, exactly like the receipt handler does.
// PUT /pharmacy/settings/labels
func (h *Handler) UpdateLabelSettings(c *gin.Context) {
	principal, ok := auth.PrincipalFromContext(c)
	if !ok || principal.PharmacyID == "" || principal.ID == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_mutation_account_required", "message": "حساب مدير أو موظف صيدلية مطلوب"})
		return
	}

	var payload struct {
		Labels *labelSettings `json:"labels"`
	}
	if err := c.ShouldBindJSON(&payload); err != nil || payload.Labels == nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_settings_payload",
			"message": "صيغة إعدادات الملصقات غير صحيحة",
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

	current, _, err := h.readLabelSettings(c.Request.Context(), principal.PharmacyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "settings_query_failed",
			"message": "تعذر تحميل إعدادات الملصقات",
		})
		return
	}

	normalized, validationMessage := normalizeLabelSettings(*payload.Labels, current)
	if validationMessage != "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_label_settings",
			"message": validationMessage,
		})
		return
	}

	doc["labels"] = normalized
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
			"message": "تعذر حفظ إعدادات الملصقات",
		})
		return
	}

	// label_template.* audit events (Final Decision 14).
	tx, err := h.db.Begin(c.Request.Context())
	if err == nil {
		if _, err := tx.Exec(c.Request.Context(), `
			SELECT set_config('app.current_pharmacy_id', $1, true),
			       set_config('app.current_user_id', $2, true)
		`, principal.PharmacyID, principal.ID); err == nil {
			if err := writeAuditLog(c.Request.Context(), tx, principal,
				"label_template.updated", "update", "pharmacy_settings", "",
				map[string]any{"custom_templates": len(normalized.Templates), "default_template_id": normalized.DefaultTemplateID},
				"تحديث قوالب الملصقات"); err != nil {
				auditFailure("label_template.updated", err)
			}
			if err := tx.Commit(c.Request.Context()); err != nil {
				auditFailure("label_template.updated commit", err)
			}
		} else {
			_ = tx.Rollback(c.Request.Context())
			auditFailure("label_template.updated scope", err)
		}
	} else {
		auditFailure("label_template.updated tx", err)
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{"labels": normalized}})
}
