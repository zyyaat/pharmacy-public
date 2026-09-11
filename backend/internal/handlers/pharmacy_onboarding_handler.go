package handlers

import (
        "context"
        "encoding/json"
        "errors"
        "net/http"
        "strings"
        "time"
        "unicode/utf8"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
)

// Task 57 — onboarding الوردة الأولى بعد التحقق من البريد: صفحة إعداد
// الصيدلية التي تُفتح تلقائيًا لكل حساب جديد. بيانات الملف تُكتب على أعمدة
// pharmacies الحقيقية (phone/website/address/city...)، وحالة الإكمال تُحفظ
// في مساحة "onboarding" داخل settings JSONB — نفس نمط مساحة "receipt":
// المستند يُقرأ ويُعدّل ويُكتب من Go لضمان الحفاظ على المساحات المجهولة.
//
// GET  /api/v1/pharmacy/onboarding  → الحالة الحالية + بيانات الملف
// PUT  /api/v1/pharmacy/onboarding  → حفظ (كامل مع complete=true أو مسودة)

const onboardingMarker = "onboarding"

type onboardingProfile struct {
        Name          string `json:"name"`
        Phone         string `json:"phone"`
        Website       string `json:"website"`
        AddressLine1  string `json:"address_line1"`
        AddressLine2  string `json:"address_line2"`
        City          string `json:"city"`
        StateProvince string `json:"state_province"`
        PostalCode    string `json:"postal_code"`
        Country       string `json:"country"`
}

func onboardingCompleted(doc map[string]any) bool {
        section, ok := doc[onboardingMarker]
        if !ok {
                return false
        }
        blob, err := json.Marshal(section)
        if err != nil {
                return false
        }
        var stored struct {
                Completed bool `json:"completed"`
        }
        return json.Unmarshal(blob, &stored) == nil && stored.Completed
}

func nullIfEmpty(value string) *string {
        if strings.TrimSpace(value) == "" {
                return nil
        }
        return &value
}

// loadOnboardingRow reads the pharmacy profile columns and its settings
// document in one query. Returns pgx.ErrNoRows when the pharmacy is gone.
func (h *Handler) loadOnboardingRow(ctx context.Context, pharmacyID string) (onboardingProfile, map[string]any, error) {
        var (
                profile  onboardingProfile
                settings []byte
                legal    string
        )
        err := h.db.QueryRow(ctx, `
                SELECT name, COALESCE(legal_name, ''), COALESCE(phone, ''), COALESCE(website, ''),
                       COALESCE(address_line1, ''), COALESCE(address_line2, ''),
                       COALESCE(city, ''), COALESCE(state_province, ''),
                       COALESCE(postal_code, ''), COALESCE(country, ''), settings
                FROM pharmacies
                WHERE id = $1 AND is_active = true
        `, pharmacyID).Scan(
                &profile.Name, &legal, &profile.Phone, &profile.Website,
                &profile.AddressLine1, &profile.AddressLine2,
                &profile.City, &profile.StateProvince,
                &profile.PostalCode, &profile.Country, &settings,
        )
        if err != nil {
                return profile, nil, err
        }
        doc := map[string]any{}
        if len(settings) > 0 {
                if err := json.Unmarshal(settings, &doc); err != nil {
                        // مستند تالف لا يجب أن يُسقط الإعداد: نبدأ من مستند فارغ والدفعة
                        // القادمة تعيد كتابته كما هو الحال في مساحة receipt.
                        doc = map[string]any{}
                }
        }
        return profile, doc, nil
}

func (h *Handler) respondOnboarding(c *gin.Context, status int, profile onboardingProfile, doc map[string]any) {
        c.JSON(status, gin.H{"data": gin.H{
                "onboarding_required": !onboardingCompleted(doc),
                "pharmacy":            profile,
        }})
}

// GetPharmacyOnboarding backs the first screen of the post-verification
// wizard: the client prefills every field with whatever the pharmacy
// already has and learns whether the setup is still pending.
func (h *Handler) GetPharmacyOnboarding(c *gin.Context) {
        principal, ok := pharmacyPrincipal(c)
        if !ok {
                return
        }
        ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
        defer cancel()
        profile, doc, err := h.loadOnboardingRow(ctx, principal.PharmacyID)
        if err != nil {
                if errors.Is(err, pgx.ErrNoRows) {
                        c.JSON(http.StatusNotFound, gin.H{"error": "pharmacy_not_found", "message": "لا توجد صيدلية مرتبطة بهذا الحساب"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "onboarding_query_failed", "message": "تعذر تحميل بيانات الصيدلية"})
                return
        }
        h.respondOnboarding(c, http.StatusOK, profile, doc)
}

// UpdatePharmacyOnboarding writes the profile collected by the wizard and,
// when complete=true, closes the onboarding gate so the dashboard stops
// redirecting the owner back to the setup page.
func (h *Handler) UpdatePharmacyOnboarding(c *gin.Context) {
        principal, ok := pharmacyPrincipal(c)
        if !ok {
                return
        }
        var payload struct {
                Name          *string `json:"name"`
                Phone         *string `json:"phone"`
                Website       *string `json:"website"`
                AddressLine1  *string `json:"address_line1"`
                AddressLine2  *string `json:"address_line2"`
                City          *string `json:"city"`
                StateProvince *string `json:"state_province"`
                PostalCode    *string `json:"postal_code"`
                Complete      bool    `json:"complete"`
        }
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_onboarding_payload", "message": "صيغة بيانات الإعداد غير صحيحة"})
                return
        }

        ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
        defer cancel()
        current, doc, err := h.loadOnboardingRow(ctx, principal.PharmacyID)
        if err != nil {
                if errors.Is(err, pgx.ErrNoRows) {
                        c.JSON(http.StatusNotFound, gin.H{"error": "pharmacy_not_found", "message": "لا توجد صيدلية مرتبطة بهذا الحساب"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "onboarding_query_failed", "message": "تعذر تحميل بيانات الصيدلية"})
                return
        }

        // الاسم وحده المطلوب (وهو موجود أصلًا من التسجيل) — كل الحقول الأخرى
        // اختيارية كي يظل زر «تخطي الآن» في المعالج ممكنًا دون فشل خفي.
        merged := current
        if payload.Name != nil {
                merged.Name = strings.TrimSpace(*payload.Name)
        }
        if utf8.RuneCountInString(merged.Name) < 2 || utf8.RuneCountInString(merged.Name) > 255 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_name", "message": "اسم الصيدلية مطلوب (حرفان على الأقل و255 حرفًا كحد أقصى)"})
                return
        }
        fields := []struct {
                value *string
                max   int
                label string
        }{{payload.Phone, 50, "رقم الهاتف"}, {payload.Website, 255, "الموقع الإلكتروني"},
                {payload.AddressLine1, 255, "العنوان"}, {payload.AddressLine2, 255, "العنوان الإضافي"},
                {payload.City, 100, "المدينة"}, {payload.StateProvince, 100, "المنطقة"},
                {payload.PostalCode, 20, "الرمز البريدي"}}
        updates := map[*string]*string{
                payload.Phone:         &merged.Phone,
                payload.Website:       &merged.Website,
                payload.AddressLine1:  &merged.AddressLine1,
                payload.AddressLine2:  &merged.AddressLine2,
                payload.City:          &merged.City,
                payload.StateProvince: &merged.StateProvince,
                payload.PostalCode:    &merged.PostalCode,
        }
        for _, field := range fields {
                if field.value == nil {
                        continue
                }
                trimmed := strings.TrimSpace(*field.value)
                if utf8.RuneCountInString(trimmed) > field.max {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_field", "message": field.label + " أطول من الحد المسموح"})
                        return
                }
                *updates[field.value] = trimmed
        }

        if payload.Complete {
                doc[onboardingMarker] = gin.H{
                        "completed":    true,
                        "completed_at": time.Now().UTC().Format(time.RFC3339),
                }
        }
        blob, err := json.Marshal(doc)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "settings_encode_failed", "message": "تعذر حفظ الإعدادات"})
                return
        }

        tag, err := h.db.Exec(ctx, `
                UPDATE pharmacies SET
                        name = $2, phone = $3, website = $4,
                        address_line1 = $5, address_line2 = $6,
                        city = $7, state_province = $8, postal_code = $9,
                        settings = $10::jsonb, updated_at = NOW()
                WHERE id = $1 AND is_active = true
        `, principal.PharmacyID, merged.Name,
                nullIfEmpty(merged.Phone), nullIfEmpty(merged.Website),
                nullIfEmpty(merged.AddressLine1), nullIfEmpty(merged.AddressLine2),
                nullIfEmpty(merged.City), nullIfEmpty(merged.StateProvince),
                nullIfEmpty(merged.PostalCode), string(blob))
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "onboarding_update_failed", "message": "تعذر حفظ بيانات الصيدلية"})
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "pharmacy_not_found", "message": "لا توجد صيدلية مرتبطة بهذا الحساب"})
                return
        }

        h.respondOnboarding(c, http.StatusOK, merged, doc)
}
