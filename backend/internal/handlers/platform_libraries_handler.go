// Platform-admin central product libraries («مكتبات المنتجات المركزية»).
//
// The catalog (global_products) existed from day one as a shared,
// cross-tenant table but had NO management surface: it only grew from
// pharmacy-side creation/import, hardcoding category='medication' and
// prescription='no' on the way. This handler gives the super admin the
// missing control room: named libraries (country-targeted, versioned,
// publishable), the OFFICIAL regulated price per library entry, and an
// append-only change log that the pharmacy sync phase diffs against.
//
// Version semantics (locked by migration 31, honored by every writer):
//   - a library starts at version 1, unpublished; while unpublished ALL
//     edits are tagged with the CURRENT version (drafting v1),
//   - after the first publish, edits tag version+1 (drafting the next
//     release) and publish moves the version forward only when draft
//     changes exist — no empty releases,
//   - pharmacies (next phase) diff against version > last_synced AND
//     version <= library.version so draft rows never leak.
//
// Every mutation is transactional and audited to platform_audit_logs
// (the tenant writeAuditLog can never host platform events — migration 30).
package handlers

import (
        "context"
        "errors"
        "net/http"
        "strconv"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/pharmacy-os/backend/internal/auth"
)

// ---------------------------------------------------------------------------
// Shared helpers (used by the products/import handler file too)
// ---------------------------------------------------------------------------

// libraryDraftVersion returns the version number new edits should be tagged
// with, locking the library row FOR UPDATE so concurrent publishers serialize.
func libraryDraftVersion(ctx context.Context, tx pgx.Tx, libraryID string) (int, bool, error) {
        var version int
        var published bool
        err := tx.QueryRow(ctx,
                `SELECT version, is_published FROM product_libraries WHERE id = $1::uuid FOR UPDATE`,
                libraryID,
        ).Scan(&version, &published)
        if err != nil {
                return 0, false, err
        }
        if !published {
                return version, false, nil
        }
        return version + 1, true, nil
}

// logLibraryChange appends one change-log row tagged with the version the
// change belongs to. oldP/newP are nil for non-price changes.
func logLibraryChange(ctx context.Context, tx pgx.Tx, libraryID, globalProductID string, version int, changeType string, oldP, newP *int64, summary string) error {
        _, err := tx.Exec(ctx, `
                INSERT INTO library_changes
                        (library_id, global_product_id, version, change_type, old_price_piastres, new_price_piastres, summary)
                VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, NULLIF($7, ''))
        `, libraryID, globalProductID, version, changeType, oldP, newP, summary)
        return err
}

// touchLibrary keeps updated_at honest for UI sorting.
func touchLibrary(ctx context.Context, tx pgx.Tx, libraryID string) error {
        _, err := tx.Exec(ctx, `UPDATE product_libraries SET updated_at = NOW() WHERE id = $1::uuid`, libraryID)
        return err
}

// normalizeLibraryCountry trims/upcases the free-form country (same column
// format as pharmacies.country); empty becomes NULL = «عامة لكل الدول».
func normalizeLibraryCountry(raw string) *string {
        v := strings.ToUpper(strings.TrimSpace(raw))
        if v == "" {
                return nil
        }
        return &v
}

// currencyExists validates against the live currency_code enum so the Go
// side can never drift from the SQL type (migration 1 owns the list).
func currencyExists(ctx context.Context, q dbQuerier, code string) (bool, error) {
        var ok bool
        err := q.QueryRow(ctx,
                `SELECT EXISTS (SELECT 1 FROM unnest(enum_range(NULL::currency_code)) AS v(label) WHERE label::text = $1)`,
                code,
        ).Scan(&ok)
        return ok, err
}

// parsePositiveInt reads a page-ish query parameter with a fallback.
func parsePositiveInt(raw string, def int) int {
        v, err := strconv.Atoi(strings.TrimSpace(raw))
        if err != nil || v < 1 {
                return def
        }
        return v
}

// ---------------------------------------------------------------------------
// Libraries CRUD + publishing + change log
// ---------------------------------------------------------------------------

type libraryPayload struct {
        Name        string `json:"name"`
        Description string `json:"description"`
        CountryCode string `json:"country_code"`
        Currency    string `json:"currency"`
}

func (p *libraryPayload) normalize() {
        p.Name = strings.TrimSpace(p.Name)
        p.Description = strings.TrimSpace(p.Description)
        if p.Currency == "" {
                p.Currency = "EGP"
        }
}

type libraryRow struct {
        ID               string     `json:"id"`
        Name             string     `json:"name"`
        Description      *string    `json:"description"`
        CountryCode      *string    `json:"country_code"`
        Currency         string     `json:"currency"`
        IsPublished      bool       `json:"is_published"`
        Version          int        `json:"version"`
        PublishedAt      *time.Time `json:"published_at"`
        ProductCount     int64      `json:"product_count"`
        SyncedPharmacies int64      `json:"synced_pharmacies"`
        DraftChanges     int64      `json:"draft_changes"`
        CreatedAt        time.Time  `json:"created_at"`
        UpdatedAt        time.Time  `json:"updated_at"`
}

const librarySelectBody = `
        SELECT l.id::text, l.name, l.description, l.country_code, l.currency::text,
               l.is_published, l.version, l.published_at, l.created_at, l.updated_at,
               (SELECT COUNT(*) FROM library_products lp WHERE lp.library_id = l.id) AS product_count,
               (SELECT COUNT(*) FROM pharmacy_library_syncs s WHERE s.library_id = l.id) AS synced_pharmacies,
               (SELECT COUNT(*) FROM library_changes c
                  WHERE c.library_id = l.id
                    AND c.version = CASE WHEN l.is_published THEN l.version + 1 ELSE l.version END) AS draft_changes
        FROM product_libraries l
`

func scanLibraryRow(row pgx.Row) (*libraryRow, error) {
        var r libraryRow
        err := row.Scan(&r.ID, &r.Name, &r.Description, &r.CountryCode, &r.Currency,
                &r.IsPublished, &r.Version, &r.PublishedAt, &r.CreatedAt, &r.UpdatedAt,
                &r.ProductCount, &r.SyncedPharmacies, &r.DraftChanges)
        if err != nil {
                return nil, err
        }
        return &r, nil
}

// ListPlatformLibraries — GET /platform-admin/libraries
func (h *Handler) ListPlatformLibraries(c *gin.Context) {
        rows, err := h.db.Query(c.Request.Context(), librarySelectBody+`ORDER BY l.created_at DESC`)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "libraries_query_failed"})
                return
        }
        defer rows.Close()

        libs := []*libraryRow{}
        for rows.Next() {
                r, err := scanLibraryRow(rows)
                if err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "libraries_scan_failed"})
                        return
                }
                libs = append(libs, r)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "libraries_scan_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": libs})
}

// CreatePlatformLibrary — POST /platform-admin/libraries
func (h *Handler) CreatePlatformLibrary(c *gin.Context) {
        var payload libraryPayload
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        payload.normalize()
        if payload.Name == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_library", "message": "اسم المكتبة مطلوب"})
                return
        }
        ok, err := currencyExists(c.Request.Context(), h.db, payload.Currency)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "currency_check_failed"})
                return
        }
        if !ok {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_currency", "message": "العملة غير معروفة"})
                return
        }
        country := normalizeLibraryCountry(payload.CountryCode)

        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        var id string
        err = tx.QueryRow(ctx, `
                INSERT INTO product_libraries (name, description, country_code, currency, created_by)
                VALUES ($1, NULLIF($2, ''), $3, $4, NULLIF($5, ''))
                RETURNING id::text
        `, payload.Name, payload.Description, country, payload.Currency, principal.ID).Scan(&id)
        if err != nil {
                if isUniqueViolation(err) {
                        c.JSON(http.StatusConflict, gin.H{"error": "library_name_taken", "message": "توجد مكتبة بنفس الاسم لنفس نطاق الدولة"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_create_failed"})
                return
        }
        if err := writePlatformAuditLog(ctx, tx, principal,
                "library.create", "create", "product_library", id, "",
                map[string]any{"name": payload.Name, "country_code": country, "currency": payload.Currency},
                "إنشاء مكتبة منتجات: "+payload.Name); err != nil {
                _ = tx.Rollback(ctx)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }

        r, err := scanLibraryRow(h.db.QueryRow(ctx, librarySelectBody+`WHERE l.id = $1::uuid`, id))
        if err != nil {
                c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id}})
                return
        }
        c.JSON(http.StatusCreated, gin.H{"data": r})
}

// GetPlatformLibrary — GET /platform-admin/libraries/:id
func (h *Handler) GetPlatformLibrary(c *gin.Context) {
        r, err := scanLibraryRow(h.db.QueryRow(c.Request.Context(),
                librarySelectBody+`WHERE l.id = $1::uuid`, c.Param("id")))
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_found", "message": "المكتبة غير موجودة"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_query_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": r})
}

// UpdatePlatformLibrary — PUT /platform-admin/libraries/:id
// Metadata only: library name/description/country/currency are NOT part of
// the pharmacy sync diff (the diff tracks catalog+price changes), so this
// writes no library_changes rows.
func (h *Handler) UpdatePlatformLibrary(c *gin.Context) {
        var payload libraryPayload
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        payload.normalize()
        if payload.Name == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_library", "message": "اسم المكتبة مطلوب"})
                return
        }
        ok, err := currencyExists(c.Request.Context(), h.db, payload.Currency)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "currency_check_failed"})
                return
        }
        if !ok {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_currency", "message": "العملة غير معروفة"})
                return
        }
        country := normalizeLibraryCountry(payload.CountryCode)

        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        tag, err := tx.Exec(ctx, `
                UPDATE product_libraries
                SET name = $2, description = NULLIF($3, ''), country_code = $4, currency = $5, updated_at = NOW()
                WHERE id = $1::uuid
        `, c.Param("id"), payload.Name, payload.Description, country, payload.Currency)
        if err != nil {
                if isUniqueViolation(err) {
                        c.JSON(http.StatusConflict, gin.H{"error": "library_name_taken", "message": "توجد مكتبة بنفس الاسم لنفس نطاق الدولة"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_update_failed"})
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_found", "message": "المكتبة غير موجودة"})
                return
        }
        if err := writePlatformAuditLog(ctx, tx, principal,
                "library.update", "update", "product_library", c.Param("id"), "",
                map[string]any{"name": payload.Name, "country_code": country, "currency": payload.Currency},
                "تعديل بيانات مكتبة: "+payload.Name); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }

        r, err := scanLibraryRow(h.db.QueryRow(ctx, librarySelectBody+`WHERE l.id = $1::uuid`, c.Param("id")))
        if err != nil {
                c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": c.Param("id")}})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": r})
}

// DeletePlatformLibrary — DELETE /platform-admin/libraries/:id
// The FK cascade removes the library's entries, change log and sync
// pointers. Pharmacies that imported from it keep every product and price
// they already pulled — they simply stop receiving updates for it. That is
// a deliberate, audited decision, never a silent data loss.
func (h *Handler) DeletePlatformLibrary(c *gin.Context) {
        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        var name string
        var synced int64
        err = tx.QueryRow(ctx, `
                SELECT l.name,
                       (SELECT COUNT(*) FROM pharmacy_library_syncs s WHERE s.library_id = l.id)
                FROM product_libraries l WHERE l.id = $1::uuid FOR UPDATE OF l
        `, c.Param("id")).Scan(&name, &synced)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_found", "message": "المكتبة غير موجودة"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_query_failed"})
                return
        }
        if _, err := tx.Exec(ctx, `DELETE FROM product_libraries WHERE id = $1::uuid`, c.Param("id")); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_delete_failed"})
                return
        }
        if err := writePlatformAuditLog(ctx, tx, principal,
                "library.delete", "delete", "product_library", c.Param("id"), "",
                map[string]any{"name": name, "synced_pharmacies": synced},
                "حذف مكتبة: "+name); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"deleted": true}})
}

// PublishPlatformLibrary — POST /platform-admin/libraries/:id/publish
// First publish makes the library visible to pharmacies at its current
// version. Later publishes release the accumulated draft changes as a new
// version — and refuse when there is nothing new (no empty releases).
func (h *Handler) PublishPlatformLibrary(c *gin.Context) {
        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        var (
                name        string
                version     int
                published   bool
                productCnt  int64
                draftCount  int64
        )
        err = tx.QueryRow(ctx, `
                SELECT l.name, l.version, l.is_published,
                       (SELECT COUNT(*) FROM library_products lp WHERE lp.library_id = l.id),
                       (SELECT COUNT(*) FROM library_changes ch
                          WHERE ch.library_id = l.id
                            AND ch.version = CASE WHEN l.is_published THEN l.version + 1 ELSE l.version END)
                FROM product_libraries l WHERE l.id = $1::uuid FOR UPDATE OF l
        `, c.Param("id")).Scan(&name, &version, &published, &productCnt, &draftCount)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_found", "message": "المكتبة غير موجودة"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_query_failed"})
                return
        }

        newVersion := version
        if !published {
                if productCnt == 0 {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "library_empty", "message": "المكتبة فارغة — أضف منتجات قبل النشر"})
                        return
                }
                if _, err := tx.Exec(ctx,
                        `UPDATE product_libraries SET is_published = true, published_at = NOW(), updated_at = NOW() WHERE id = $1::uuid`,
                        c.Param("id")); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "library_publish_failed"})
                        return
                }
        } else {
                if draftCount == 0 {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "no_changes_to_publish", "message": "لا تغييرات جديدة لنشرها كإصدار جديد"})
                        return
                }
                newVersion = version + 1
                if _, err := tx.Exec(ctx,
                        `UPDATE product_libraries SET version = version + 1, published_at = NOW(), updated_at = NOW() WHERE id = $1::uuid`,
                        c.Param("id")); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "library_publish_failed"})
                        return
                }
        }

        if err := writePlatformAuditLog(ctx, tx, principal,
                "library.publish", "update", "product_library", c.Param("id"), "",
                map[string]any{"version": newVersion, "draft_changes": draftCount, "first_publish": !published},
                "نشر مكتبة "+name+" — الإصدار "+itoa(newVersion)); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "published": true, "version": newVersion, "first_publish": !published,
        }})
}

// ListPlatformLibraryChanges — GET /platform-admin/libraries/:id/changes
// The append-only log behind the «الفرق منذ آخر مزامنة» diff screen the
// pharmacy side will render; the admin sees it as the release history.
func (h *Handler) ListPlatformLibraryChanges(c *gin.Context) {
        page := parsePositiveInt(c.Query("page"), 1)
        pageSize := parsePositiveInt(c.Query("page_size"), 20)
        if pageSize > 100 {
                pageSize = 100
        }
        ctx := c.Request.Context()

        var total int64
        if err := h.db.QueryRow(ctx,
                `SELECT COUNT(*) FROM library_changes WHERE library_id = $1::uuid`, c.Param("id"),
        ).Scan(&total); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "changes_count_failed"})
                return
        }

        rows, err := h.db.Query(ctx, `
                SELECT c.id::text, c.global_product_id::text, gp.name, c.version, c.change_type,
                       c.old_price_piastres, c.new_price_piastres, c.summary, c.created_at
                FROM library_changes c
                JOIN global_products gp ON gp.id = c.global_product_id
                WHERE c.library_id = $1::uuid
                ORDER BY c.version DESC, c.created_at DESC, c.id
                LIMIT $2 OFFSET $3
        `, c.Param("id"), pageSize, (page-1)*pageSize)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "changes_query_failed"})
                return
        }
        defer rows.Close()

        type changeRow struct {
                ID              string     `json:"id"`
                GlobalProductID string     `json:"global_product_id"`
                ProductName     string     `json:"product_name"`
                Version         int        `json:"version"`
                ChangeType      string     `json:"change_type"`
                OldPrice        *int64     `json:"old_price_piastres"`
                NewPrice        *int64     `json:"new_price_piastres"`
                Summary         *string    `json:"summary"`
                CreatedAt       time.Time  `json:"created_at"`
        }
        changes := []changeRow{}
        for rows.Next() {
                var r changeRow
                if err := rows.Scan(&r.ID, &r.GlobalProductID, &r.ProductName, &r.Version, &r.ChangeType,
                        &r.OldPrice, &r.NewPrice, &r.Summary, &r.CreatedAt); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "changes_scan_failed"})
                        return
                }
                changes = append(changes, r)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "changes_scan_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{
                "data": changes,
                "pagination": gin.H{
                        "total": total, "page": page, "page_size": pageSize,
                        "total_pages": (total + int64(pageSize) - 1) / int64(pageSize),
                },
        })
}
