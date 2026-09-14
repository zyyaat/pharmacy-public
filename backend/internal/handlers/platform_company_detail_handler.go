// Platform per-company account page (Task 15 — «التحكم الكامل»).
//
// One page per account: profile + governing subscription + per-company
// entitlement overrides + the account's own audit log. Professional SaaS
// pattern (Stripe customer-specific prices, Chargebee per-subscription
// entitlements, Schematic/Stigg per-tenant overrides): the plan is the
// company BASELINE; overrides merge ON TOP for one company without
// forking the shared plan or touching other subscribers.
//
//   GET    /platform-admin/companies/:id                    profile
//   GET    /platform-admin/companies/:id/entitlements       list overrides
//   POST   /platform-admin/companies/:id/entitlements       upsert override
//   DELETE /platform-admin/companies/:id/entitlements/:eid  remove override
//   GET    /platform-admin/companies/:id/logs               per-account audit
//
// Every mutation is transactional, audit-logged into platform_audit_logs
// (which also fixed the silent loss of ALL platform billing audit rows —
// the tenant writeAuditLog can never host platform events), and
// invalidates the company's subscription cache so enforcement reflects
// the override immediately.
package handlers

import (
        "net/http"
        "strconv"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
)

// resolvePlatformCompany validates the :id param and returns (id, name).
// Rejected with 404 when the company row is missing/soft-deleted.
func (h *Handler) resolvePlatformCompany(c *gin.Context) (string, string, bool) {
        id := strings.TrimSpace(c.Param("id"))
        var name string
        err := h.db.QueryRow(c.Request.Context(),
                `SELECT name FROM companies WHERE id = $1::uuid AND deleted_at IS NULL`, id,
        ).Scan(&name)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusNotFound, gin.H{"error": "company_not_found", "message": "الحساب غير موجود"})
                return "", "", false
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "company_lookup_failed"})
                return "", "", false
        }
        return id, name, true
}

// GetPlatformCompany returns the account page profile: the company row,
// its governing subscription + plan, live usage against limits, and the
// active override count — everything the page header needs in one call.
func (h *Handler) GetPlatformCompany(c *gin.Context) {
        id, name, ok := h.resolvePlatformCompany(c)
        if !ok {
                return
        }
        ctx := c.Request.Context()

        var nameAr, email, phone, companyStatus, legacyPlan string
        var maxUsers int
        var createdAt time.Time
        err := h.db.QueryRow(ctx, `
                SELECT COALESCE(name_ar, ''), COALESCE(email, ''), COALESCE(phone, ''),
                       status::text, COALESCE(plan::text, ''), max_users_per_account, created_at
                FROM companies WHERE id = $1::uuid
        `, id).Scan(&nameAr, &email, &phone, &companyStatus, &legacyPlan, &maxUsers, &createdAt)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "company_query_failed"})
                return
        }

        // Governing subscription (live row if any, else newest terminal row)
        // — the same "effective view" the subscriptions list shows, so the
        // page never contradicts the table it was opened from.
        var sub gin.H
        var subRow *gin.H
        rows, err := h.db.Query(ctx, `
                SELECT s.id::text, s.status, s.billing_interval,
                       s.current_period_start, s.current_period_end, s.trial_ends_at,
                       s.cancel_at_period_end, s.source, s.created_at,
                       p.id::text, p.slug, p.name, COALESCE(p.name_ar, '')
                FROM subscriptions s
                JOIN plans p ON p.id = s.plan_id
                WHERE s.company_id = $1::uuid
                ORDER BY CASE WHEN s.status IN ('pending','trial','active') THEN 0 ELSE 1 END,
                         s.created_at DESC
                LIMIT 1
        `, id)
        if err == nil {
                defer rows.Close()
                for rows.Next() {
                        var sid, status, interval, source, planID, planSlug, planName, planNameAr string
                        var periodStart, periodEnd, trialEndsAt *time.Time
                        var cancelAtPeriodEnd bool
                        var subCreated time.Time
                        if err := rows.Scan(&sid, &status, &interval, &periodStart, &periodEnd,
                                &trialEndsAt, &cancelAtPeriodEnd, &source, &subCreated,
                                &planID, &planSlug, &planName, &planNameAr); err == nil {
                                subRow = &gin.H{
                                        "id": sid, "status": status, "billing_interval": interval,
                                        "current_period_start": timePtrJSON(periodStart),
                                        "current_period_end":   timePtrJSON(periodEnd),
                                        "trial_ends_at":        timePtrJSON(trialEndsAt),
                                        "cancel_at_period_end": cancelAtPeriodEnd,
                                        "source":               source, "created_at": subCreated.UTC().Format(time.RFC3339),
                                        "plan": gin.H{"id": planID, "slug": planSlug, "name": planName, "name_ar": planNameAr},
                                }
                        }
                }
        }
        if subRow != nil {
                sub = *subRow
        }

        // Usage vs limits — the page shows live meters, the same counters
        // the limit gate enforces.
        usage := map[string]int{}
        if h.subs != nil {
                if u, err := h.subs.UsageAll(ctx, id); err == nil {
                        usage = u
                }
        }

        var activeOverrides int
        _ = h.db.QueryRow(ctx, `
                SELECT COUNT(*)::int FROM company_entitlements
                WHERE company_id = $1::uuid AND (expires_at IS NULL OR expires_at > NOW())
        `, id).Scan(&activeOverrides)

        data := gin.H{
                "id": id, "name": name, "name_ar": nameAr, "email": email, "phone": phone,
                "status": companyStatus, "legacy_plan": legacyPlan,
                "max_users_per_account": maxUsers,
                "created_at":            createdAt.UTC().Format(time.RFC3339),
                "subscription":          sub,
                "usage":                 usage,
                "active_overrides":      activeOverrides,
        }
        c.JSON(http.StatusOK, gin.H{"data": data})
}

// ListCompanyEntitlements returns ALL override rows for the account,
// including expired ones (marked) so the operator sees history, not just
// the live state.
func (h *Handler) ListCompanyEntitlements(c *gin.Context) {
        id, _, ok := h.resolvePlatformCompany(c)
        if !ok {
                return
        }
        rows, err := h.db.Query(c.Request.Context(), `
                SELECT e.id::text, e.kind, e.key, e.enabled, e.value,
                       COALESCE(e.reason, ''), e.expires_at, e.created_by_email, e.created_at,
                       COALESCE(e.bundle_key, '')
                FROM company_entitlements e
                WHERE e.company_id = $1::uuid
                ORDER BY e.created_at DESC
        `, id)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlements_query_failed"})
                return
        }
        defer rows.Close()

        entitlements := make([]gin.H, 0)
        now := time.Now()
        for rows.Next() {
                var eid, kind, key, reason, createdBy, bundleKey string
                var enabled *bool
                var value *int
                var expiresAt *time.Time
                var createdAt time.Time
                if err := rows.Scan(&eid, &kind, &key, &enabled, &value,
                        &reason, &expiresAt, &createdBy, &createdAt, &bundleKey); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlements_scan_failed"})
                        return
                }
                item := gin.H{
                        "id": eid, "kind": kind, "key": key,
                        "enabled": enabled, "value": value, "reason": reason,
                        "expires_at": timePtrJSON(expiresAt),
                        "created_by": createdBy,
                        "created_at": createdAt.UTC().Format(time.RFC3339),
                        "expired":    expiresAt != nil && now.After(*expiresAt),
                        "bundle_key": bundleKey,
                }
                entitlements = append(entitlements, item)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlements_iterate_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": entitlements})
}

type companyEntitlementPayload struct {
        Kind      string     `json:"kind"`
        Key       string     `json:"key"`
        Enabled   *bool      `json:"enabled"`
        Value     *int       `json:"value"`
        Reason    string     `json:"reason"`
        ExpiresAt *time.Time `json:"expires_at"`
}

// UpsertCompanyEntitlement creates or updates ONE override row
// (company_id + kind + key is unique). Validation mirrors the DB CHECKs
// and verifies the key against its catalog so a typo never silently
// grants nothing. Cache invalidation makes the effect immediate.
func (h *Handler) UpsertCompanyEntitlement(c *gin.Context) {
        id, name, ok := h.resolvePlatformCompany(c)
        if !ok {
                return
        }
        var body companyEntitlementPayload
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        body.Kind = strings.TrimSpace(body.Kind)
        body.Key = strings.TrimSpace(body.Key)
        body.Reason = strings.TrimSpace(body.Reason)

        ctx := c.Request.Context()
        switch body.Kind {
        case "feature":
                if body.Key == "" {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_key", "message": "مفتاح الميزة مطلوب"})
                        return
                }
                var exists bool
                if err := h.db.QueryRow(ctx,
                        `SELECT EXISTS (SELECT 1 FROM features WHERE key = $1)`, body.Key).Scan(&exists); err != nil || !exists {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_key", "message": "ميزة غير معروفة: " + body.Key})
                        return
                }
                if body.Enabled == nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "enabled_required", "message": "حدد منح الميزة أو منعها"})
                        return
                }
        case "permission":
                if body.Key == "" {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_key", "message": "مفتاح الصلاحية مطلوب"})
                        return
                }
                var exists bool
                if err := h.db.QueryRow(ctx,
                        `SELECT EXISTS (SELECT 1 FROM permissions WHERE key = $1)`, body.Key).Scan(&exists); err != nil || !exists {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_key", "message": "صلاحية غير معروفة: " + body.Key})
                        return
                }
                if body.Enabled == nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "enabled_required", "message": "حدد منح الصلاحية أو منعها"})
                        return
                }
        case "limit":
                switch body.Key {
                case models.LimitKeyBranches, models.LimitKeyUsers,
                        models.LimitKeyEmployees, models.LimitKeyProducts:
                default:
                        c.JSON(http.StatusBadRequest, gin.H{
                                "error":   "invalid_key",
                                "message": "مفتاح الحدود يجب أن يكون أحد: branches, users, employees, products",
                        })
                        return
                }
                // 0 would collide with "not configured = unlimited" in
                // LimitAllowed — reject it loudly instead of a silent no-op.
                if body.Value == nil || *body.Value < -1 || *body.Value == 0 {
                        c.JSON(http.StatusBadRequest, gin.H{
                                "error":   "value_invalid",
                                "message": "قيمة الحد يجب أن تكون رقمًا موجبًا أو -1 لغير محدود",
                        })
                        return
                }
        default:
                c.JSON(http.StatusBadRequest, gin.H{
                        "error":   "invalid_kind",
                        "message": "النوع يجب أن يكون أحد: feature, permission, limit",
                })
                return
        }

        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var eid string
        err = tx.QueryRow(ctx, `
                INSERT INTO company_entitlements
                        (company_id, kind, key, enabled, value, reason, expires_at, created_by, created_by_email)
                VALUES ($1::uuid, $2, $3, $4, $5, NULLIF($6, ''), $7, $8, $9)
                ON CONFLICT (company_id, kind, key) DO UPDATE SET
                        enabled = EXCLUDED.enabled,
                        value = EXCLUDED.value,
                        reason = EXCLUDED.reason,
                        expires_at = EXCLUDED.expires_at,
                        updated_at = NOW()
                RETURNING id::text
        `, id, body.Kind, body.Key, body.Enabled, body.Value, body.Reason, body.ExpiresAt,
                principal.ID, principal.Email).Scan(&eid)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlement_upsert_failed", "detail": err.Error()})
                return
        }

        summary := "استثناء " + body.Kind + " " + body.Key
        switch body.Kind {
        case "feature", "permission":
                if body.Enabled != nil && *body.Enabled {
                        summary = "منح " + body.Kind + " " + body.Key
                } else {
                        summary = "منع " + body.Kind + " " + body.Key
                }
        case "limit":
                if body.Value != nil {
                        summary = "تعديل حد " + body.Key + " إلى "
                        if *body.Value == -1 {
                                summary += "غير محدود"
                        } else {
                                summary += strconv.Itoa(*body.Value)
                        }
                }
        }
        if body.Reason != "" {
                summary += " — " + body.Reason
        }

        // Feature overrides bundle their derived permissions (atomic grant/
        // deny): a feature granted without its feature_permissions would show
        // the module in the sidebar while every API call 403s — the Task-13
        // failure mode reproduced per-account. Bundled rows carry
        // bundle_key='feature:<key>' so deleting the feature row removes the
        // whole bundle; the plan editor remains the tool for editing the
        // BASELINE itself, overrides only ever stack on top of it.
        if body.Kind == "feature" {
                bundle := "feature:" + body.Key
                if body.Enabled != nil && *body.Enabled {
                        // deny rows on the same keys from a previous deny-bundle must
                        // not survive a new grant: clear the old bundle first.
                        if _, err := tx.Exec(ctx, `
                                DELETE FROM company_entitlements
                                WHERE company_id = $1::uuid AND kind = 'permission' AND bundle_key = $2
                        `, id, bundle); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlement_bundle_failed"})
                                return
                        }
                        if _, err := tx.Exec(ctx, `
                                INSERT INTO company_entitlements
                                        (company_id, kind, key, enabled, value, reason, expires_at, bundle_key, created_by, created_by_email)
                                SELECT $1::uuid, 'permission', p.key, TRUE, NULL, $2, $3, $4, $5, $6
                                FROM feature_permissions fp
                                JOIN permissions p ON p.id = fp.permission_id
                                WHERE fp.feature_key = $7
                                ON CONFLICT (company_id, kind, key) DO UPDATE SET
                                        enabled = TRUE,
                                        reason = EXCLUDED.reason,
                                        expires_at = EXCLUDED.expires_at,
                                        bundle_key = EXCLUDED.bundle_key,
                                        updated_at = NOW()
                        `, id, body.Reason, body.ExpiresAt, bundle, principal.ID, principal.Email, body.Key); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlement_bundle_failed", "detail": err.Error()})
                                return
                        }
                } else {
                        // Deny-bundle: every derived permission explicitly denied.
                        if _, err := tx.Exec(ctx, `
                                INSERT INTO company_entitlements
                                        (company_id, kind, key, enabled, value, reason, expires_at, bundle_key, created_by, created_by_email)
                                SELECT $1::uuid, 'permission', p.key, FALSE, NULL, $2, $3, $4, $5, $6
                                FROM feature_permissions fp
                                JOIN permissions p ON p.id = fp.permission_id
                                WHERE fp.feature_key = $7
                                ON CONFLICT (company_id, kind, key) DO UPDATE SET
                                        enabled = FALSE,
                                        reason = EXCLUDED.reason,
                                        expires_at = EXCLUDED.expires_at,
                                        bundle_key = EXCLUDED.bundle_key,
                                        updated_at = NOW()
                        `, id, body.Reason, body.ExpiresAt, bundle, principal.ID, principal.Email, body.Key); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlement_bundle_failed", "detail": err.Error()})
                                return
                        }
                }
                summary += " + صلاحياتها المشتقة"
        }

        _ = writePlatformAuditLog(ctx, tx, principal, "entitlement."+body.Kind, "billing",
                "company_entitlement", eid, id,
                map[string]any{"kind": body.Kind, "key": body.Key,
                        "enabled": body.Enabled, "value": body.Value,
                        "reason": body.Reason, "expires_at": body.ExpiresAt},
                summary+" ("+name+")")

        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlement_commit_failed"})
                return
        }
        if h.subs != nil {
                h.subs.Invalidate(id)
        }
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{"id": eid}})
}

// DeleteCompanyEntitlement removes an override — the account falls back to
// the plan baseline for that key immediately (cache invalidated).
func (h *Handler) DeleteCompanyEntitlement(c *gin.Context) {
        id, name, ok := h.resolvePlatformCompany(c)
        if !ok {
                return
        }
        eid := strings.TrimSpace(c.Param("eid"))

        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer tx.Rollback(ctx)

        var kind, key, bundleKey *string
        err = tx.QueryRow(ctx, `
                DELETE FROM company_entitlements
                WHERE id = $1::uuid AND company_id = $2::uuid
                RETURNING kind, key, bundle_key
        `, eid, id).Scan(&kind, &key, &bundleKey)
        if err == pgx.ErrNoRows {
                c.JSON(http.StatusNotFound, gin.H{"error": "entitlement_not_found"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlement_delete_failed"})
                return
        }
        // Cascade: a FEATURE override owns its bundled permission rows —
        // removing the feature falls the whole bundle back to the baseline.
        if kind != nil && *kind == "feature" {
                if _, err := tx.Exec(ctx, `
                        DELETE FROM company_entitlements
                        WHERE company_id = $1::uuid AND kind = 'permission' AND bundle_key = $2
                `, id, "feature:"+*key); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlement_cascade_failed"})
                        return
                }
        }

        _ = writePlatformAuditLog(ctx, tx, principal, "entitlement.remove", "billing",
                "company_entitlement", eid, id,
                map[string]any{"kind": kind, "key": key},
                "حذف استثناء "+deref(kind)+" "+deref(key)+" — العودة لخطة الأساس ("+name+")")

        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "entitlement_commit_failed"})
                return
        }
        if h.subs != nil {
                h.subs.Invalidate(id)
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": eid, "deleted": true}})
}

// ListCompanyLogs returns THIS account's audit trail only — platform
// billing events (plan assignment, lifecycle actions, manual payments,
// refunds, overrides) are written to platform_audit_logs with
// company_id = this account. No other company's rows can appear: the
// filter is a hard WHERE on company_id, not a client-side slice.
func (h *Handler) ListCompanyLogs(c *gin.Context) {
        id, _, ok := h.resolvePlatformCompany(c)
        if !ok {
                return
        }
        page, pageSize := pagination(c)
        rows, err := h.db.Query(c.Request.Context(), `
                SELECT a.id::text, a.action, a.entity_type, a.entity_id,
                       COALESCE(NULLIF(a.changes_summary, ''), a.action),
                       COALESCE(NULLIF(a.actor_display_name, ''), NULLIF(a.actor_email, ''), 'System'),
                       a.created_at
                FROM platform_audit_logs a
                WHERE a.company_id = $1::uuid
                ORDER BY a.created_at DESC
                LIMIT $2 OFFSET $3
        `, id, pageSize, (page-1)*pageSize)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "company_logs_query_failed"})
                return
        }
        defer rows.Close()

        var total int
        _ = h.db.QueryRow(c.Request.Context(),
                `SELECT COUNT(*)::int FROM platform_audit_logs WHERE company_id = $1::uuid`, id).Scan(&total)

        logs := make([]gin.H, 0)
        for rows.Next() {
                var lid, action, entityType, entityID, summary, actor string
                var createdAt time.Time
                if err := rows.Scan(&lid, &action, &entityType, &entityID,
                        &summary, &actor, &createdAt); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "company_logs_scan_failed"})
                        return
                }
                logs = append(logs, gin.H{
                        "id": lid, "action": action, "entity_type": entityType,
                        "entity_id": entityID, "summary": summary, "actor": actor,
                        "created_at": createdAt.UTC().Format(time.RFC3339),
                })
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "company_logs_iterate_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": logs, "pagination": gin.H{
                "page": page, "page_size": pageSize, "total": total,
        }})
}

// deref renders a nullable string column ("", "x") for audit summaries.
func deref(s *string) string {
        if s == nil {
                return ""
        }
        return *s
}
