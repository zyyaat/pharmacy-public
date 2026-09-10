package handlers

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// pharmacyProfile is the editable core information of the pharmacy and its
// main branch: real tenant data stored in the pharmacies/branches tables,
// not UI strings — so it intentionally never changes with the interface
// language. The registration flow seeds the branch name as «الفرع الرئيسي»
// and the pharmacy name from the signup form; this handler is the supported
// way to correct them later (sidebar, receipts and reports read from here).
type pharmacyProfile struct {
	Name       string `json:"name"`
	Phone      string `json:"phone"`
	Email      string `json:"email"`
	Address    string `json:"address"`
	City       string `json:"city"`
	BranchName string `json:"branch_name"`
}

// Limits mirror the VARCHAR widths of the underlying columns (runes, not
// bytes, so Arabic names are measured fairly).
const (
	profileMaxName    = 255
	profileMaxPhone   = 50
	profileMaxEmail   = 255
	profileMaxAddress = 255
	profileMaxCity    = 100
)

func trimProfileField(s string, max int) (string, bool) {
	s = strings.TrimSpace(s)
	if len([]rune(s)) > max {
		return "", false
	}
	return s, true
}

// normalize validates the payload and returns the cleaned profile.
func (p pharmacyProfile) normalize() (pharmacyProfile, string) {
	out := p

	var ok bool
	if out.Name, ok = trimProfileField(out.Name, profileMaxName); !ok || out.Name == "" {
		return out, "اسم الصيدلية مطلوب (بحد أقصى 255 حرفاً)"
	}
	if out.BranchName, ok = trimProfileField(out.BranchName, profileMaxName); !ok || out.BranchName == "" {
		return out, "اسم الفرع الرئيسي مطلوب (بحد أقصى 255 حرفاً)"
	}
	if out.Phone, ok = trimProfileField(out.Phone, profileMaxPhone); !ok {
		return out, "رقم الهاتف أطول من الحد المسموح (50 حرفاً)"
	}
	if out.Email, ok = trimProfileField(out.Email, profileMaxEmail); !ok {
		return out, "البريد الإلكتروني أطول من الحد المسموح (255 حرفاً)"
	}
	if out.Email != "" && (!strings.Contains(out.Email, "@") || strings.ContainsAny(out.Email, " \t")) {
		return out, "صيغة البريد الإلكتروني غير صحيحة"
	}
	if out.Address, ok = trimProfileField(out.Address, profileMaxAddress); !ok {
		return out, "العنوان أطول من الحد المسموح (255 حرفاً)"
	}
	if out.City, ok = trimProfileField(out.City, profileMaxCity); !ok {
		return out, "المدينة أطول من الحد المسموح (100 حرف)"
	}
	return out, ""
}

// GetPharmacyProfile returns the editable pharmacy + main branch information
// for the session principal. Reading is open to every pharmacy principal —
// the same data is already visible through /pharmacy/context.
func (h *Handler) GetPharmacyProfile(c *gin.Context) {
	principal, ok := pharmacyPrincipal(c)
	if !ok {
		return
	}

	profile, found, err := h.readPharmacyProfile(c.Request.Context(), principal.PharmacyID)
	if err != nil || !found {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "profile_query_failed",
			"message": "تعذر تحميل معلومات الصيدلية",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": profile})
}

func (h *Handler) readPharmacyProfile(ctx context.Context, pharmacyID string) (pharmacyProfile, bool, error) {
	var profile pharmacyProfile
	err := h.db.QueryRow(ctx, `
		SELECT p.name, COALESCE(p.phone, ''), COALESCE(p.email, ''),
		       COALESCE(p.address_line1, ''), COALESCE(p.city, ''),
		       COALESCE(b.name, '')
		FROM pharmacies p
		LEFT JOIN branches b ON b.id = p.default_branch_id AND b.is_active = true
		WHERE p.id = $1 AND p.is_active = true
	`, pharmacyID).Scan(
		&profile.Name, &profile.Phone, &profile.Email,
		&profile.Address, &profile.City, &profile.BranchName,
	)
	if err != nil {
		return profile, false, err
	}
	return profile, true, nil
}

// UpdatePharmacyProfile replaces the editable pharmacy information and the
// main branch name in one transaction. Writing follows the same mutation
// guard + CSRF + settings.general permission as the rest of the settings.
func (h *Handler) UpdatePharmacyProfile(c *gin.Context) {
	principal, ok := pharmacyPrincipal(c)
	if !ok {
		return
	}

	var payload pharmacyProfile
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_profile_payload",
			"message": "صيغة بيانات الصيدلية غير صحيحة",
		})
		return
	}

	normalized, validationMessage := payload.normalize()
	if validationMessage != "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_pharmacy_profile",
			"message": validationMessage,
		})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "profile_update_failed",
			"message": "تعذر حفظ معلومات الصيدلية",
		})
		return
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx, `
		UPDATE pharmacies
		SET name = $2, phone = NULLIF($3, ''), email = NULLIF($4, ''),
		    address_line1 = NULLIF($5, ''), city = NULLIF($6, ''), updated_at = NOW()
		WHERE id = $1 AND is_active = true
	`, principal.PharmacyID, normalized.Name, normalized.Phone, normalized.Email,
		normalized.Address, normalized.City)
	if err != nil || tag.RowsAffected() == 0 {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "profile_update_failed",
			"message": "تعذر حفظ معلومات الصيدلية",
		})
		return
	}

	// The main branch (default_branch_id) name is what the sidebar and the
	// receipts header display. Only the default branch is renamed here —
	// sub-branches keep their own names.
	tag, err = tx.Exec(ctx, `
		UPDATE branches
		SET name = $2, updated_at = NOW()
		WHERE pharmacy_id = $1 AND id = (SELECT default_branch_id FROM pharmacies WHERE id = $1)
		  AND is_active = true
	`, principal.PharmacyID, normalized.BranchName)
	if err != nil || tag.RowsAffected() == 0 {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "profile_update_failed",
			"message": "تعذر حفظ اسم الفرع الرئيسي",
		})
		return
	}

	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "profile_update_failed",
			"message": "تعذر حفظ معلومات الصيدلية",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": normalized})
}
