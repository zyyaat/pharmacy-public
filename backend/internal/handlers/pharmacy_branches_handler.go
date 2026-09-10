package handlers

import (
        "context"
        "errors"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5/pgconn"
)

// Task 50 — إدارة الفروع الحقيقية: الفروع بيانات مستقلة قابلة للإضافة والتعديل،
// والفرع الرئيسي (default_branch_id) هو مقر الصيدلية: تعديله يحدّث بيانات
// الصيدلية نفسها (الاسم عبر pharmacy_name + التواصل والعنوان) التي يعرضها
// الشريط الجانبي ويطبعها رأس الفاتورة — بدل شاشة معلومات منفصلة.
type branchPayload struct {
        Name         string `json:"name"`
        Code         string `json:"code"`
        Phone        string `json:"phone"`
        Email        string `json:"email"`
        Address      string `json:"address"`
        City         string `json:"city"`
        PharmacyName string `json:"pharmacy_name"`
}

const (
        branchMaxName    = 255
        branchMaxCode    = 50
        branchMaxPhone   = 50
        branchMaxEmail   = 255
        branchMaxAddress = 255
        branchMaxCity    = 100
)

func trimBranchField(s string, max int) (string, bool) {
        s = strings.TrimSpace(s)
        if len([]rune(s)) > max {
                return "", false
        }
        return s, true
}

func (p branchPayload) normalize() (branchPayload, string) {
        out := p
        var ok bool
        if out.Name, ok = trimBranchField(out.Name, branchMaxName); !ok || out.Name == "" {
                return out, "اسم الفرع مطلوب (بحد أقصى 255 حرفاً)"
        }
        if out.Code, ok = trimBranchField(out.Code, branchMaxCode); !ok {
                return out, "رمز الفرع أطول من الحد المسموح (50 حرفاً)"
        }
        if out.Phone, ok = trimBranchField(out.Phone, branchMaxPhone); !ok {
                return out, "رقم الهاتف أطول من الحد المسموح (50 حرفاً)"
        }
        if out.Email, ok = trimBranchField(out.Email, branchMaxEmail); !ok {
                return out, "البريد الإلكتروني أطول من الحد المسموح (255 حرفاً)"
        }
        if out.Email != "" && (!strings.Contains(out.Email, "@") || strings.ContainsAny(out.Email, " \t")) {
                return out, "صيغة البريد الإلكتروني غير صحيحة"
        }
        if out.Address, ok = trimBranchField(out.Address, branchMaxAddress); !ok {
                return out, "العنوان أطول من الحد المسموح (255 حرفاً)"
        }
        if out.City, ok = trimBranchField(out.City, branchMaxCity); !ok {
                return out, "المدينة أطول من الحد المسموح (100 حرف)"
        }
        if out.PharmacyName, ok = trimBranchField(out.PharmacyName, branchMaxName); !ok {
                return out, "اسم الصيدلية أطول من الحد المسموح (255 حرفاً)"
        }
        return out, ""
}

func branchWriteError(c *gin.Context, message string) {
        c.JSON(http.StatusInternalServerError, gin.H{
                "error":   "branch_write_failed",
                "message": message,
        })
}

func isUniqueViolation(err error) bool {
        var pgErr *pgconn.PgError
        return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// CreatePharmacyBranch adds a new sub-branch to the session pharmacy.
// POST /pharmacy/branches — perm: branches.create
func (h *Handler) CreatePharmacyBranch(c *gin.Context) {
        principal, ok := pharmacyPrincipal(c)
        if !ok {
                return
        }
        var payload branchPayload
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_branch_payload", "message": "صيغة بيانات الفرع غير صحيحة"})
                return
        }
        normalized, validationMessage := payload.normalize()
        if validationMessage != "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_branch", "message": validationMessage})
                return
        }

        ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
        defer cancel()

        var id string
        err := h.db.QueryRow(ctx, `
                INSERT INTO branches (pharmacy_id, name, code, phone, email, address_line1, city, country)
                VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, ''), NULLIF($5, ''), NULLIF($6, ''), NULLIF($7, ''),
                        COALESCE((SELECT country FROM pharmacies WHERE id = $1), 'EG'))
                RETURNING id::text
        `, principal.PharmacyID, normalized.Name, normalized.Code, normalized.Phone,
                normalized.Email, normalized.Address, normalized.City).Scan(&id)
        if err != nil {
                if isUniqueViolation(err) {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "branch_code_conflict", "message": "رمز الفرع مستخدم بالفعل في فرع آخر — اختر رمزاً مختلفاً"})
                        return
                }
                branchWriteError(c, "تعذر إضافة الفرع")
                return
        }

        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "id": id, "name": normalized.Name, "code": normalized.Code,
                "phone": normalized.Phone, "email": normalized.Email,
                "address": normalized.Address, "city": normalized.City,
                "is_active": true, "is_main": false, "manager_name": "",
        }})
}

// UpdatePharmacyBranch edits an existing branch. Editing the main branch also
// refreshes the pharmacy-level information (name via pharmacy_name + contact
// details) so the sidebar and receipts stay coherent with what was edited.
// PUT /pharmacy/branches/:id — perm: branches.update
func (h *Handler) UpdatePharmacyBranch(c *gin.Context) {
        principal, ok := pharmacyPrincipal(c)
        if !ok {
                return
        }
        branchID := c.Param("id")
        var payload branchPayload
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_branch_payload", "message": "صيغة بيانات الفرع غير صحيحة"})
                return
        }
        normalized, validationMessage := payload.normalize()
        if validationMessage != "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_branch", "message": validationMessage})
                return
        }

        ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
        defer cancel()

        tx, err := h.db.Begin(ctx)
        if err != nil {
                branchWriteError(c, "تعذر حفظ بيانات الفرع")
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        var isMain bool
        err = tx.QueryRow(ctx, `
                SELECT COALESCE(p.default_branch_id = b.id, false)
                FROM branches b
                JOIN pharmacies p ON p.id = b.pharmacy_id
                WHERE b.id = $1::uuid AND b.pharmacy_id = $2 AND b.is_active = true
        `, branchID, principal.PharmacyID).Scan(&isMain)
        if err != nil {
                c.JSON(http.StatusNotFound, gin.H{"error": "branch_not_found", "message": "الفرع غير موجود"})
                return
        }

        tag, err := tx.Exec(ctx, `
                UPDATE branches
                SET name = $2, code = NULLIF($3, ''), phone = NULLIF($4, ''), email = NULLIF($5, ''),
                    address_line1 = NULLIF($6, ''), city = NULLIF($7, ''), updated_at = NOW()
                WHERE id = $1::uuid AND pharmacy_id = $8 AND is_active = true
        `, branchID, normalized.Name, normalized.Code, normalized.Phone,
                normalized.Email, normalized.Address, normalized.City, principal.PharmacyID)
        if err != nil {
                if isUniqueViolation(err) {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "branch_code_conflict", "message": "رمز الفرع مستخدم بالفعل في فرع آخر — اختر رمزاً مختلفاً"})
                        return
                }
                branchWriteError(c, "تعذر حفظ بيانات الفرع")
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "branch_not_found", "message": "الفرع غير موجود"})
                return
        }

        var pharmacyName string
        if isMain {
                // الفرع الرئيسي هو مقر الصيدلية: بيانات التواصل تتزامن مع سجل الصيدلية
                // (الفواتير والشريط الجانبي يقرأون منها)، والاسم عبر pharmacy_name صراحةً.
                pharmacyName = normalized.PharmacyName
                if pharmacyName == "" {
                        pharmacyName = normalized.Name
                }
                if _, err := tx.Exec(ctx, `
                        UPDATE pharmacies
                        SET name = $2, phone = NULLIF($3, ''), email = NULLIF($4, ''),
                            address_line1 = NULLIF($5, ''), city = NULLIF($6, ''), updated_at = NOW()
                        WHERE id = $1 AND is_active = true
                `, principal.PharmacyID, pharmacyName, normalized.Phone, normalized.Email,
                        normalized.Address, normalized.City); err != nil {
                        branchWriteError(c, "تعذر حفظ معلومات الصيدلية")
                        return
                }
        }

        if err := tx.Commit(ctx); err != nil {
                branchWriteError(c, "تعذر حفظ بيانات الفرع")
                return
        }

        data := gin.H{
                "id": branchID, "name": normalized.Name, "code": normalized.Code,
                "phone": normalized.Phone, "email": normalized.Email,
                "address": normalized.Address, "city": normalized.City,
                "is_active": true, "is_main": isMain,
        }
        if isMain {
                data["pharmacy_name"] = pharmacyName
        }
        c.JSON(http.StatusOK, gin.H{"data": data})
}

// DeletePharmacyBranch deactivates a sub-branch (soft delete — rows stay for
// historical references like employees and movements). The main branch can
// never be deleted. DELETE /pharmacy/branches/:id — perm: branches.delete
func (h *Handler) DeletePharmacyBranch(c *gin.Context) {
        principal, ok := pharmacyPrincipal(c)
        if !ok {
                return
        }
        branchID := c.Param("id")

        ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
        defer cancel()

        var isMain bool
        err := h.db.QueryRow(ctx, `
                SELECT COALESCE(p.default_branch_id = b.id, false)
                FROM branches b
                JOIN pharmacies p ON p.id = b.pharmacy_id
                WHERE b.id = $1::uuid AND b.pharmacy_id = $2 AND b.is_active = true
        `, branchID, principal.PharmacyID).Scan(&isMain)
        if err != nil {
                c.JSON(http.StatusNotFound, gin.H{"error": "branch_not_found", "message": "الفرع غير موجود"})
                return
        }
        if isMain {
                c.JSON(http.StatusBadRequest, gin.H{
                        "error":   "branch_main_protected",
                        "message": "لا يمكن حذف الفرع الرئيسي — عدّل بياناته بدلاً من حذفه",
                })
                return
        }

        tag, err := h.db.Exec(ctx, `
                UPDATE branches SET is_active = false, updated_at = NOW()
                WHERE id = $1::uuid AND pharmacy_id = $2 AND is_active = true
        `, branchID, principal.PharmacyID)
        if err != nil || tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "branch_not_found", "message": "الفرع غير موجود"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": branchID, "is_active": false}})
}
