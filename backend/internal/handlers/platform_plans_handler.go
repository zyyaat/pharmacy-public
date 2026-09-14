// Platform-admin plans & subscriptions management (Task 90).
//
// Everything the super admin needs to run the SaaS commercially WITHOUT
// code changes: create/edit/activate plans (name, pricing, features,
// permissions, limits), inspect and override subscriptions, and register
// manual payments until the Paymob integration lands (its webhook will
// perform the same subscription transitions automatically).
//
// All mutations are transactional, audit-logged, and invalidate the
// subscription cache so enforcement reflects the change immediately.
package handlers

import (
        "context"
        "encoding/json"
        "fmt"
        "net/http"
        "regexp"
        "strings"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
)

var planSlugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{1,48}$`)

// dbQuerier is the minimal read surface shared by the pool and tx.
type dbQuerier interface {
        QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

func decodePlanSets(featuresRaw, limitsRaw []byte) ([]string, map[string]int) {
        features := []string{}
        limits := map[string]int{}
        _ = json.Unmarshal(featuresRaw, &features)
        _ = json.Unmarshal(limitsRaw, &limits)
        return features, limits
}

func verifyFeaturesExist(ctx context.Context, db dbQuerier, keys []string) error {
        for _, key := range keys {
                var exists bool
                if err := db.QueryRow(ctx,
                        `SELECT EXISTS (SELECT 1 FROM features WHERE key = $1)`, key).Scan(&exists); err != nil {
                        return err
                }
                if !exists {
                        return fmt.Errorf("feature_not_found:%s", key)
                }
        }
        return nil
}

func verifyPermissionsExist(ctx context.Context, db dbQuerier, keys []string) error {
        for _, key := range keys {
                var exists bool
                if err := db.QueryRow(ctx,
                        `SELECT EXISTS (SELECT 1 FROM permissions WHERE key = $1)`, key).Scan(&exists); err != nil {
                        return err
                }
                if !exists {
                        return fmt.Errorf("permission_not_found:%s", key)
                }
        }
        return nil
}

func verifyLimits(limits map[string]int) error {
        for key, value := range limits {
                if strings.TrimSpace(key) == "" {
                        return fmt.Errorf("limit_key_empty")
                }
                if value != -1 && value <= 0 {
                        return fmt.Errorf("limit_value_invalid:%s", key)
                }
        }
        return nil
}

// ---------------------------------------------------------------------------
// Features catalog
// ---------------------------------------------------------------------------

// ListPlatformFeatures returns the feature catalog with its permission
// suggestions — the plan editor's building blocks.
func (h *Handler) ListPlatformFeatures(c *gin.Context) {
        rows, err := h.db.Query(c.Request.Context(), `
                SELECT f.key, f.name, COALESCE(f.name_ar, ''), COALESCE(f.description, ''), f.sort_order, f.is_active,
                       COALESCE((SELECT jsonb_agg(p.key ORDER BY p.key)
                                 FROM feature_permissions fp
                                 JOIN permissions p ON p.id = fp.permission_id
                                 WHERE fp.feature_key = f.key), '[]'::jsonb)
                FROM features f
                ORDER BY f.sort_order, f.key
        `)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "features_query_failed"})
                return
        }
        defer rows.Close()

        features := make([]gin.H, 0)
        for rows.Next() {
                var key, name, nameAr, description string
                var sortOrder int
                var isActive bool
                var permsRaw []byte
                if err := rows.Scan(&key, &name, &nameAr, &description, &sortOrder, &isActive, &permsRaw); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "features_scan_failed"})
                        return
                }
                suggestions := []string{}
                _ = json.Unmarshal(permsRaw, &suggestions)
                features = append(features, gin.H{
                        "key": key, "name": name, "name_ar": nameAr,
                        "description": description, "sort_order": sortOrder,
                        "is_active": isActive, "suggested_permissions": suggestions,
                })
        }
        c.JSON(http.StatusOK, gin.H{"data": features})
}

// ---------------------------------------------------------------------------
// Plans CRUD
// ---------------------------------------------------------------------------

// ListPlatformPlans returns every plan (including inactive) with live
// subscriber counts.
func (h *Handler) ListPlatformPlans(c *gin.Context) {
        rows, err := h.db.Query(c.Request.Context(), `
                SELECT p.id::text, p.slug, p.name, COALESCE(p.name_ar, ''), COALESCE(p.description, ''),
                       p.monthly_price_piastres, p.yearly_price_piastres, p.currency,
                       p.is_active, p.is_public, p.sort_order, p.created_at, p.updated_at, p.deleted_at,
                       COALESCE((SELECT COUNT(*)::int FROM subscriptions s
                                 WHERE s.plan_id = p.id AND s.status IN ('trial','active')), 0)
                FROM plans p
                ORDER BY p.sort_order, p.created_at
        `)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plans_query_failed"})
                return
        }
        defer rows.Close()

        plans := make([]gin.H, 0)
        for rows.Next() {
                var plan models.Plan
                var subscribers int
                if err := rows.Scan(&plan.ID, &plan.Slug, &plan.Name, &plan.NameAr, &plan.Description,
                        &plan.MonthlyPricePiastres, &plan.YearlyPricePiastres, &plan.Currency,
                        &plan.IsActive, &plan.IsPublic, &plan.SortOrder, &plan.CreatedAt, &plan.UpdatedAt,
                        &plan.DeletedAt, &subscribers); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "plans_scan_failed"})
                        return
                }
                plans = append(plans, gin.H{
                        "id": plan.ID, "slug": plan.Slug, "name": plan.Name,
                        "name_ar": plan.NameAr, "description": plan.Description,
                        "monthly_price_piastres": plan.MonthlyPricePiastres,
                        "yearly_price_piastres":  plan.YearlyPricePiastres,
                        "currency":               plan.Currency,
                        "is_active":              plan.IsActive,
                        "is_public":              plan.IsPublic,
                        "sort_order":             plan.SortOrder,
                        "created_at":             plan.CreatedAt,
                        "updated_at":             plan.UpdatedAt,
                        "deleted_at":             plan.DeletedAt,
                        "subscribers":            subscribers,
                })
        }
        c.JSON(http.StatusOK, gin.H{"data": plans})
}

// GetPlatformPlan returns one plan with its full editable sets.
func (h *Handler) GetPlatformPlan(c *gin.Context) {
        id := c.Param("id")
        var subscribers int
        var featuresRaw, permsRaw, limitsRaw []byte
        var plan models.Plan
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT p.id::text, p.slug, p.name, COALESCE(p.name_ar, ''), COALESCE(p.description, ''),
                       p.monthly_price_piastres, p.yearly_price_piastres, p.currency,
                       p.is_active, p.is_public, p.sort_order, p.created_at, p.updated_at, p.deleted_at,
                       COALESCE((SELECT COUNT(*)::int FROM subscriptions s
                                 WHERE s.plan_id = p.id AND s.status IN ('trial','active')), 0),
                       COALESCE((SELECT jsonb_agg(pf.feature_key ORDER BY pf.feature_key)
                                 FROM plan_features pf WHERE pf.plan_id = p.id), '[]'::jsonb),
                       COALESCE((SELECT jsonb_agg(p2.key ORDER BY p2.key)
                                 FROM plan_permissions pp JOIN permissions p2 ON p2.id = pp.permission_id
                                 WHERE pp.plan_id = p.id), '[]'::jsonb),
                       COALESCE((SELECT jsonb_object_agg(pl.limit_key, pl.value)
                                 FROM plan_limits pl WHERE pl.plan_id = p.id), '{}'::jsonb)
                FROM plans p WHERE p.id = $1
        `, id).Scan(&plan.ID, &plan.Slug, &plan.Name, &plan.NameAr, &plan.Description,
                &plan.MonthlyPricePiastres, &plan.YearlyPricePiastres, &plan.Currency,
                &plan.IsActive, &plan.IsPublic, &plan.SortOrder, &plan.CreatedAt, &plan.UpdatedAt,
                &plan.DeletedAt, &subscribers, &featuresRaw, &permsRaw, &limitsRaw)
        if err != nil {
                if err == pgx.ErrNoRows {
                        c.JSON(http.StatusNotFound, gin.H{"error": "plan_not_found"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_query_failed"})
                return
        }
        features, limits := decodePlanSets(featuresRaw, limitsRaw)
        permissions := []string{}
        _ = json.Unmarshal(permsRaw, &permissions)

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "id": plan.ID, "slug": plan.Slug, "name": plan.Name,
                "name_ar": plan.NameAr, "description": plan.Description,
                "monthly_price_piastres": plan.MonthlyPricePiastres,
                "yearly_price_piastres":  plan.YearlyPricePiastres,
                "currency":               plan.Currency,
                "is_active":              plan.IsActive,
                "is_public":              plan.IsPublic,
                "sort_order":             plan.SortOrder,
                "features":               features,
                "permissions":            permissions,
                "limits":                 limits,
                "subscribers":            subscribers,
        }})
}

type platformPlanPayload struct {
        Slug                 string         `json:"slug"`
        Name                 string         `json:"name"`
        NameAr               string         `json:"name_ar"`
        Description          string         `json:"description"`
        MonthlyPricePiastres int64          `json:"monthly_price_piastres"`
        YearlyPricePiastres  int64          `json:"yearly_price_piastres"`
        Currency             string         `json:"currency"`
        IsActive             *bool          `json:"is_active"`
        IsPublic             *bool          `json:"is_public"`
        SortOrder            *int           `json:"sort_order"`
        Features             []string       `json:"features"`
        Permissions          []string       `json:"permissions"`
        Limits               map[string]int `json:"limits"`
}

func (p *platformPlanPayload) normalize() {
        p.Slug = strings.TrimSpace(p.Slug)
        p.Name = strings.TrimSpace(p.Name)
        p.NameAr = strings.TrimSpace(p.NameAr)
        if p.Currency == "" {
                p.Currency = "EGP"
        }
}

func (p *platformPlanPayload) validate(requireSlug bool, isActive, isPublic bool) string {
        if requireSlug && !planSlugPattern.MatchString(p.Slug) {
                return "المعرّف (slug) مطلوب: حروف صغيرة وأرقام وشرطات فقط"
        }
        if p.Name == "" {
                return "اسم الخطة مطلوب"
        }
        if p.MonthlyPricePiastres < 0 || p.YearlyPricePiastres < 0 {
                return "الأسعار لا يمكن أن تكون سالبة"
        }
        // Best practice (Stripe/Paddle model): a plan offered on the public
        // pricing page must carry at least one positive price — a 0/0 plan
        // renders as "0 EGP" and dead-ends at checkout (intention creation
        // refuses zero-amount payments). Private/inactive plans may stay
        // unpriced: they are assigned manually or hidden from self-serve.
        if isActive && isPublic && p.MonthlyPricePiastres <= 0 && p.YearlyPricePiastres <= 0 {
                return "الخطة المفعّلة والظاهرة في صفحة الأسعار تحتاج سعرًا واحدًا على الأقل (شهريًا أو سنويًا) — أدخل سعرًا أو اجعلها غير ظاهرة أو عطّلها"
        }
        if err := verifyLimits(p.Limits); err != nil {
                return "قيم الحدود يجب أن تكون عددًا موجبًا أو -1 لغير محدود"
        }
        return ""
}

// CreatePlatformPlan creates a plan with its sets in one transaction.
func (h *Handler) CreatePlatformPlan(c *gin.Context) {
        var payload platformPlanPayload
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        payload.normalize()
        // create defaults — same values the INSERT below falls back to
        createActive, createPublic := true, true
        if payload.IsActive != nil {
                createActive = *payload.IsActive
        }
        if payload.IsPublic != nil {
                createPublic = *payload.IsPublic
        }
        if msg := payload.validate(true, createActive, createPublic); msg != "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_plan", "message": msg})
                return
        }
        ctx := c.Request.Context()
        if err := verifyFeaturesExist(ctx, h.db, payload.Features); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_plan", "message": "ميزة غير معروفة: " + err.Error()})
                return
        }
        if err := verifyPermissionsExist(ctx, h.db, payload.Permissions); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_plan", "message": "صلاحية غير معروفة: " + err.Error()})
                return
        }

        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        isActive, isPublic := createActive, createPublic
        sortOrder := 0
        if payload.SortOrder != nil {
                sortOrder = *payload.SortOrder
        }

        var id string
        if err := tx.QueryRow(ctx, `
                INSERT INTO plans (slug, name, name_ar, description,
                                   monthly_price_piastres, yearly_price_piastres,
                                   currency, is_active, is_public, sort_order)
                VALUES ($1,$2,NULLIF($3,''),NULLIF($4,''),$5,$6,$7,$8,$9,$10)
                RETURNING id::text
        `, payload.Slug, payload.Name, payload.NameAr, payload.Description,
                payload.MonthlyPricePiastres, payload.YearlyPricePiastres,
                payload.Currency, isActive, isPublic, sortOrder).Scan(&id); err != nil {
                if strings.Contains(err.Error(), "duplicate key") {
                        c.JSON(http.StatusConflict, gin.H{"error": "plan_slug_taken", "message": "المعرّف مستخدم بالفعل"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_create_failed"})
                return
        }
        if err := replacePlanSets(ctx, tx, id, payload.Features, payload.Permissions, payload.Limits); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_sets_failed"})
                return
        }
        _ = writePlatformAuditLog(ctx, tx, principal, "plan.create", "billing", "plan", id, "",
                map[string]any{"slug": payload.Slug, "name": payload.Name},
                "إنشاء خطة "+payload.Name)
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_commit_failed"})
                return
        }
        h.subs.InvalidateAll()
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{"id": id, "slug": payload.Slug}})
}

// UpdatePlatformPlan atomically replaces plan fields and all three sets.
func (h *Handler) UpdatePlatformPlan(c *gin.Context) {
        id := c.Param("id")
        var payload platformPlanPayload
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        payload.normalize()
        ctx := c.Request.Context()
        // Effective visibility: the payload flag when sent, otherwise the
        // value already stored (nil means "keep current" in the UPDATE).
        effectiveActive, effectivePublic := false, false
        if err := h.db.QueryRow(ctx,
                `SELECT is_active, is_public FROM plans WHERE id = $1 AND deleted_at IS NULL`, id,
        ).Scan(&effectiveActive, &effectivePublic); err != nil {
                if err == pgx.ErrNoRows {
                        c.JSON(http.StatusNotFound, gin.H{"error": "plan_not_found"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_query_failed"})
                return
        }
        if payload.IsActive != nil {
                effectiveActive = *payload.IsActive
        }
        if payload.IsPublic != nil {
                effectivePublic = *payload.IsPublic
        }
        if msg := payload.validate(false, effectiveActive, effectivePublic); msg != "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_plan", "message": msg})
                return
        }
        if err := verifyFeaturesExist(ctx, h.db, payload.Features); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_plan", "message": "ميزة غير معروفة: " + err.Error()})
                return
        }
        if err := verifyPermissionsExist(ctx, h.db, payload.Permissions); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_plan", "message": "صلاحية غير معروفة: " + err.Error()})
                return
        }

        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        tag, err := tx.Exec(ctx, `
                UPDATE plans SET
                    name = $2, name_ar = NULLIF($3,''), description = NULLIF($4,''),
                    monthly_price_piastres = $5, yearly_price_piastres = $6,
                    currency = $7,
                    is_active = COALESCE($8, is_active),
                    is_public = COALESCE($9, is_public),
                    sort_order = COALESCE($10, sort_order),
                    updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `, id, payload.Name, payload.NameAr, payload.Description,
                payload.MonthlyPricePiastres, payload.YearlyPricePiastres,
                payload.Currency, payload.IsActive, payload.IsPublic, payload.SortOrder)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_update_failed"})
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "plan_not_found"})
                return
        }
        if err := replacePlanSets(ctx, tx, id, payload.Features, payload.Permissions, payload.Limits); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_sets_failed"})
                return
        }
        _ = writePlatformAuditLog(ctx, tx, principal, "plan.update", "billing", "plan", id, "",
                map[string]any{"name": payload.Name},
                "تعديل خطة "+payload.Name)
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_commit_failed"})
                return
        }
        h.subs.InvalidateAll()
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id}})
}

// replacePlanSets wipes and rewrites the three plan sets inside a tx.
func replacePlanSets(ctx context.Context, tx pgx.Tx, planID string,
        features []string, permissions []string, limits map[string]int) error {
        if _, err := tx.Exec(ctx, `DELETE FROM plan_features WHERE plan_id = $1`, planID); err != nil {
                return err
        }
        if _, err := tx.Exec(ctx, `DELETE FROM plan_permissions WHERE plan_id = $1`, planID); err != nil {
                return err
        }
        if _, err := tx.Exec(ctx, `DELETE FROM plan_limits WHERE plan_id = $1`, planID); err != nil {
                return err
        }
        for _, key := range features {
                if _, err := tx.Exec(ctx, `
                        INSERT INTO plan_features (plan_id, feature_key)
                        VALUES ($1, $2) ON CONFLICT DO NOTHING
                `, planID, key); err != nil {
                        return err
                }
        }
        for _, key := range permissions {
                if _, err := tx.Exec(ctx, `
                        INSERT INTO plan_permissions (plan_id, permission_id)
                        SELECT $1, p.id FROM permissions p WHERE p.key = $2
                        ON CONFLICT DO NOTHING
                `, planID, key); err != nil {
                        return err
                }
        }
        for key, value := range limits {
                if _, err := tx.Exec(ctx, `
                        INSERT INTO plan_limits (plan_id, limit_key, value)
                        VALUES ($1, $2, $3)
                        ON CONFLICT (plan_id, limit_key) DO UPDATE SET value = EXCLUDED.value
                `, planID, key, value); err != nil {
                        return err
                }
        }
        return nil
}

// UpdatePlatformPlanStatus activates/deactivates a plan. Deactivation only
// stops NEW subscriptions — existing subscribers keep their plan (decision #7).
func (h *Handler) UpdatePlatformPlanStatus(c *gin.Context) {
        id := c.Param("id")
        var body struct {
                IsActive *bool `json:"is_active"`
        }
        if err := c.ShouldBindJSON(&body); err != nil || body.IsActive == nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "is_active مطلوب"})
                return
        }
        tag, err := h.db.Exec(c.Request.Context(), `
                UPDATE plans SET is_active = $2, updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `, id, *body.IsActive)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_status_failed"})
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "plan_not_found"})
                return
        }
        h.subs.InvalidateAll()
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id, "is_active": *body.IsActive}})
}

// DeletePlatformPlan soft-deletes a plan; rejected while live subscribers exist.
func (h *Handler) DeletePlatformPlan(c *gin.Context) {
        id := c.Param("id")
        var live int
        if err := h.db.QueryRow(c.Request.Context(), `
                SELECT COUNT(*)::int FROM subscriptions
                WHERE plan_id = $1 AND status IN ('trial','active')
        `, id).Scan(&live); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_check_failed"})
                return
        }
        if live > 0 {
                c.JSON(http.StatusConflict, gin.H{
                        "error":       "plan_has_subscribers",
                        "message":     fmt.Sprintf("لا يمكن حذف خطة عليها %d مشترك حي — عطّلها بدلاً من حذفها", live),
                        "subscribers": live,
                })
                return
        }
        tag, err := h.db.Exec(c.Request.Context(), `
                UPDATE plans SET deleted_at = NOW(), is_active = FALSE, updated_at = NOW()
                WHERE id = $1 AND deleted_at IS NULL
        `, id)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "plan_delete_failed"})
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "plan_not_found"})
                return
        }
        h.subs.InvalidateAll()
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id, "deleted": true}})
}

