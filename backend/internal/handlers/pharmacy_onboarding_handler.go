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
// Task 79 — درس شكوى «بيانات المعالج ليست الكاملة اللي في صفحة تعديل الفرع»:
// المعالج كان يكتب pharmacies فقط ولا يلمس الفرع الرئيسي، فيفتح المالك صفحة
// تعديل الفرع بعده ويجد كود الفرع والبريد واسم الفرع وأدوات التواصل فارغة
// (قيم التسجيل الافتراضية «الفرع الرئيسي»/MAIN). صار الـ PUT يستقبل كذلك
// email/branch_name/branch_code ويكتبها، ويزامن الفرع الرئيسي (الهاتف/العنوان/
// المدينة) بنفس دلالات مزامنة تعديل الفرع الرئيسي العكسية — فيكون ما يجمعه
// المعالج من أول مرة هو نفسه ما تعرضه صفحة تعديل الفرع لاحقًا.
//
// GET  /api/v1/pharmacy/onboarding  → الحالة الحالية + بيانات الملف + الفرع الرئيسي
// PUT  /api/v1/pharmacy/onboarding  → حفظ (كامل مع complete=true أو مسودة)

const onboardingMarker = "onboarding"

type onboardingProfile struct {
        Name          string `json:"name"`
        Phone         string `json:"phone"`
        Website       string `json:"website"`
        Email         string `json:"email"`
        AddressLine1  string `json:"address_line1"`
        AddressLine2  string `json:"address_line2"`
        City          string `json:"city"`
        StateProvince string `json:"state_province"`
        PostalCode    string `json:"postal_code"`
        Country       string `json:"country"`
}

// onboardingBranch — بيانات الفرع الرئيسي للحفظ المسبق في المعالج (Task 79)
// وللعرض في خطوة المراجعة: نفس الحقول التي تعرضها صفحة تعديل الفرع.
type onboardingBranch struct {
        Name  string `json:"name"`
        Code  string `json:"code"`
        Email string `json:"email"`
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

// coalesceNonEmpty — نفس دلالة COALESCE(NULLIF(...)) في SQL: الفارغ يُسقط للبديل.
func coalesceNonEmpty(value, fallback string) string {
        if strings.TrimSpace(value) == "" {
                return fallback
        }
        return value
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
                       COALESCE(email, ''),
                       COALESCE(address_line1, ''), COALESCE(address_line2, ''),
                       COALESCE(city, ''), COALESCE(state_province, ''),
                       COALESCE(postal_code, ''), COALESCE(country, ''), settings
                FROM pharmacies
                WHERE id = $1 AND is_active = true
        `, pharmacyID).Scan(
                &profile.Name, &legal, &profile.Phone, &profile.Website,
                &profile.Email,
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

func (h *Handler) respondOnboarding(c *gin.Context, status int, profile onboardingProfile, doc map[string]any, branch onboardingBranch) {
        c.JSON(status, gin.H{"data": gin.H{
                "onboarding_required": !onboardingCompleted(doc),
                "pharmacy":            profile,
                "branch":              branch,
        }})
}

// loadOnboardingBranch يقرأ الفرع الرئيسي للحفظ المسبق — LEFT JOIN كي لا تفشل
// القراءة إن لم يوجد فرع (حقول فارغة) ويعود دائمًا بصفّ قابل للعرض.
func (h *Handler) loadOnboardingBranch(ctx context.Context, pharmacyID string) onboardingBranch {
        var branch onboardingBranch
        _ = h.db.QueryRow(ctx, `
                SELECT COALESCE(b.name, ''), COALESCE(b.code, ''), COALESCE(b.email, '')
                FROM pharmacies p
                LEFT JOIN branches b ON b.id = p.default_branch_id AND b.is_active = true
                WHERE p.id = $1
        `, pharmacyID).Scan(&branch.Name, &branch.Code, &branch.Email)
        return branch
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
        h.respondOnboarding(c, http.StatusOK, profile, doc, h.loadOnboardingBranch(ctx, principal.PharmacyID))
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
                Email         *string `json:"email"`
                BranchName    *string `json:"branch_name"`
                BranchCode    *string `json:"branch_code"`
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
        // حقول الفرع الرئيسي والبريد (Task 79) — نفس حدود صفحة تعديل الفرع،
        // والفراغ يعني «اترك القيمة القديمة كما هي» (دلالة COALESCE أدناه).
        branchName := ""
        if payload.BranchName != nil {
                branchName = strings.TrimSpace(*payload.BranchName)
                if utf8.RuneCountInString(branchName) > branchMaxName {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_field", "message": "اسم الفرع أطول من الحد المسموح"})
                        return
                }
        }
        branchCode := ""
        if payload.BranchCode != nil {
                branchCode = strings.TrimSpace(*payload.BranchCode)
                if utf8.RuneCountInString(branchCode) > branchMaxCode {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_field", "message": "رمز الفرع أطول من الحد المسموح (50 حرفاً)"})
                        return
                }
        }
        fields := []struct {
                value *string
                max   int
                label string
        }{{payload.Phone, 50, "رقم الهاتف"}, {payload.Website, 255, "الموقع الإلكتروني"},
                {payload.Email, branchMaxEmail, "البريد الإلكتروني"},
                {payload.AddressLine1, 255, "العنوان"}, {payload.AddressLine2, 255, "العنوان الإضافي"},
                {payload.City, 100, "المدينة"}, {payload.StateProvince, 100, "المنطقة"},
                {payload.PostalCode, 20, "الرمز البريدي"}}
        updates := map[*string]*string{
                payload.Phone:         &merged.Phone,
                payload.Website:       &merged.Website,
                payload.Email:         &merged.Email,
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
                if field.value == payload.Email && trimmed != "" &&
                        (!strings.Contains(trimmed, "@") || strings.ContainsAny(trimmed, " \t")) {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_field", "message": "صيغة البريد الإلكتروني غير صحيحة"})
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

        // معاملة واحدة: ملف الصيدلية + مزامنة الفرع الرئيسي معًا كي لا يُحفظ
        // نصف التحديث إن تعارض رمز الفرع مع فرع آخر.
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "onboarding_update_failed", "message": "تعذر حفظ بيانات الصيدلية"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        tag, err := tx.Exec(ctx, `
                UPDATE pharmacies SET
                        name = $2, phone = $3, website = $4, email = $5,
                        address_line1 = $6, address_line2 = $7,
                        city = $8, state_province = $9, postal_code = $10,
                        settings = $11::jsonb, updated_at = NOW()
                WHERE id = $1 AND is_active = true
        `, principal.PharmacyID, merged.Name,
                nullIfEmpty(merged.Phone), nullIfEmpty(merged.Website), nullIfEmpty(merged.Email),
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

        // مزامنة الفرع الرئيسي — عكس مسار «تعديل الفرع الرئيسي» في
        // pharmacy_branches_handler: الاسم والكود والبريد من حقول المعالج،
        // والتواصل والعنوان والمدينة من الملف المدموج. الفراغ يحفظ القديم.
        if _, err := tx.Exec(ctx, `
                UPDATE branches SET
                        name = COALESCE(NULLIF($2, ''), name),
                        code = COALESCE(NULLIF($3, ''), code),
                        email = COALESCE(NULLIF($4, ''), email),
                        phone = COALESCE(NULLIF($5, ''), phone),
                        address_line1 = COALESCE(NULLIF($6, ''), address_line1),
                        city = COALESCE(NULLIF($7, ''), city),
                        updated_at = NOW()
                WHERE id = (SELECT default_branch_id FROM pharmacies WHERE id = $1)
                  AND is_active = true
        `, principal.PharmacyID, branchName, branchCode, merged.Email,
                merged.Phone, merged.AddressLine1, merged.City); err != nil {
                if isUniqueViolation(err) {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "branch_code_conflict", "message": "رمز الفرع مستخدم بالفعل في فرع آخر — اختر رمزاً مختلفاً"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "onboarding_update_failed", "message": "تعذر حفظ بيانات الصيدلية"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "onboarding_update_failed", "message": "تعذر حفظ بيانات الصيدلية"})
                return
        }

        saved := h.loadOnboardingBranch(ctx, principal.PharmacyID)
        h.respondOnboarding(c, http.StatusOK, merged, doc, onboardingBranch{
                Name:  coalesceNonEmpty(branchName, saved.Name),
                Code:  coalesceNonEmpty(branchCode, saved.Code),
                Email: coalesceNonEmpty(merged.Email, saved.Email),
        })
}
