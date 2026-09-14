// Pharmacy-side central product libraries («مكتبات المنتجات») — Phase 2.
//
// The pharmacy BROWSES the libraries the platform admin published for its
// country (or universal ones), IMPORTS with the three approved gates, and
// later PULLS updates with one tap. The ownership contract is sacred here:
//
//   * stock and batches are NEVER touched — importing creates catalog
//     links and prices only, zero inventory rows,
//   * cost price belongs to the pharmacy — never written,
//   * selling price follows the official library price (pharmacy can still
//     edit it locally; the next pull restores the official value),
//   * «removed» from a library is informational — products already
//     imported stay owned by the pharmacy (red line),
//   * plan product limit is a soft gate: items beyond the ceiling come
//     back as skipped with a «upgrade» flag, never a silent failure.
//
// Dedup intelligence (gate 2) reuses the same signals as POS: exact
// barcode first, then pg_trgm name similarity with a decision threshold —
// exact global-product match means the pharmacy already has it, barcode
// match suggests LINKING instead of creating a duplicate, and a strong
// name match is surfaced as a suspect with a side-by-side comparison.
package handlers

import (
        "context"
        "errors"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"

        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/models"
)

// nameSuspectThreshold — الاسم المشابه فوق هذا الحد يُعرض كمرشّح «ربما
// نفس المنتج» للمراجعة؛ أقل من ذلك يُعد منتجًا جديدًا بلا إزعاج.
const nameSuspectThreshold = 0.55

// nameAutoLinkThreshold — فوق هذا الحد (مع غياب الباركود في الطرفين)
// المزامنة تربط تلقائيًا بدل إنشاء مكرر.
const nameAutoLinkThreshold = 0.72

// ---------------------------------------------------------------------------
// الرؤية: مكتبات منشورة تناسب بلد الصيدلية (أو عامة)
// ---------------------------------------------------------------------------

// libraryVisibilityWhere is the shared visibility predicate. $1 = pharmacy id.
// Match rule: library.country_code IS NULL OR equals the pharmacy's country
// (case/space-insensitive). Pharmacies with no country only see universal
// libraries — the UI explains the rest.
const libraryVisibilityWhere = `
        l.is_published = true
        AND (l.country_code IS NULL
             OR (ph.country IS NOT NULL AND btrim(ph.country) <> ''
                 AND UPPER(btrim(l.country_code)) = UPPER(btrim(ph.country))))
`

// syncStateSelect computes the pharmacy's per-library sync status:
// 0 = never imported, 1 = up to date, >0 = update available.
const syncStateSelect = `
        COALESCE(s.last_synced_version, 0) AS last_synced_version,
        s.synced_at AS synced_at,
        l.version - COALESCE(s.last_synced_version, 0) AS versions_behind,
        CASE
                WHEN s.id IS NULL THEN 'not_imported'
                WHEN l.version = s.last_synced_version THEN 'up_to_date'
                ELSE 'update_available'
        END AS sync_status,
        (SELECT COUNT(*) FROM library_changes dc
           WHERE dc.library_id = l.id
             AND dc.version > COALESCE(s.last_synced_version, 0)
             AND dc.version <= l.version) AS pending_changes,
        (SELECT COUNT(*) FROM library_products lp WHERE lp.library_id = l.id) AS product_count
`

// ListPharmacyLibraries — GET /pharmacy/libraries
func (h *Handler) ListPharmacyLibraries(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        rows, err := h.db.Query(c.Request.Context(), `
                SELECT l.id::text, l.name, COALESCE(l.description, ''), COALESCE(l.country_code, ''),
                       l.currency::text, l.version, l.published_at,
                       `+syncStateSelect+`
                FROM product_libraries l
                JOIN pharmacies ph ON ph.id = $1::uuid
                LEFT JOIN pharmacy_library_syncs s ON s.library_id = l.id AND s.pharmacy_id = $1::uuid
                WHERE `+libraryVisibilityWhere+`
                ORDER BY (s.id IS NULL), l.name
        `, pharmacyID)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_libraries_query_failed"})
                return
        }
        defer rows.Close()

        type item struct {
                ID                string     `json:"id"`
                Name              string     `json:"name"`
                Description       string     `json:"description"`
                CountryCode       string     `json:"country_code"`
                Currency          string     `json:"currency"`
                Version           int        `json:"version"`
                PublishedAt       *time.Time `json:"published_at"`
                LastSyncedVersion int        `json:"last_synced_version"`
                SyncedAt          *time.Time `json:"synced_at"`
                VersionsBehind    int        `json:"versions_behind"`
                SyncStatus        string     `json:"sync_status"`
                PendingChanges    int        `json:"pending_changes"`
                ProductCount      int        `json:"product_count"`
        }
        items := []item{}
        for rows.Next() {
                var r item
                if err := rows.Scan(&r.ID, &r.Name, &r.Description, &r.CountryCode, &r.Currency,
                        &r.Version, &r.PublishedAt, &r.LastSyncedVersion, &r.SyncedAt,
                        &r.VersionsBehind, &r.SyncStatus, &r.PendingChanges, &r.ProductCount); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_libraries_scan_failed"})
                        return
                }
                items = append(items, r)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_libraries_scan_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": items})
}

// GetPharmacyLibrary — GET /pharmacy/libraries/:id
func (h *Handler) GetPharmacyLibrary(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        var row struct {
                ID                string     `json:"id"`
                Name              string     `json:"name"`
                Description       string     `json:"description"`
                CountryCode       string     `json:"country_code"`
                Currency          string     `json:"currency"`
                Version           int        `json:"version"`
                PublishedAt       *time.Time `json:"published_at"`
                LastSyncedVersion int        `json:"last_synced_version"`
                SyncedAt          *time.Time `json:"synced_at"`
                VersionsBehind    int        `json:"versions_behind"`
                SyncStatus        string     `json:"sync_status"`
                PendingChanges    int        `json:"pending_changes"`
                ProductCount      int        `json:"product_count"`
        }
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT l.id::text, l.name, COALESCE(l.description, ''), COALESCE(l.country_code, ''),
                       l.currency::text, l.version, l.published_at,
                       `+syncStateSelect+`
                FROM product_libraries l
                JOIN pharmacies ph ON ph.id = $1::uuid
                LEFT JOIN pharmacy_library_syncs s ON s.library_id = l.id AND s.pharmacy_id = $1::uuid
                WHERE l.id = $2::uuid AND `+libraryVisibilityWhere+`
        `, pharmacyID, c.Param("id")).Scan(
                &row.ID, &row.Name, &row.Description, &row.CountryCode, &row.Currency,
                &row.Version, &row.PublishedAt, &row.LastSyncedVersion, &row.SyncedAt,
                &row.VersionsBehind, &row.SyncStatus, &row.PendingChanges, &row.ProductCount)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_visible", "message": "المكتبة غير متاحة لهذه الصيدلية"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_query_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": row})
}

// ListPharmacyLibraryProducts — GET /pharmacy/libraries/:id/products?search=
// What the pharmacy would import from the current published version, with a
// per-row «already have» flag and its live selling price for comparison.
func (h *Handler) ListPharmacyLibraryProducts(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        page := parsePositiveInt(c.Query("page"), 1)
        pageSize := parsePositiveInt(c.Query("page_size"), 50)
        if pageSize > 100 {
                pageSize = 100
        }
        search := escapeLike(strings.TrimSpace(c.Query("search")))
        ctx := c.Request.Context()

        where := ` AND ($2 = '' OR gp.name ILIKE '%' || $2 || '%' OR gp.generic_name ILIKE '%' || $2 || '%' OR gp.barcode ILIKE $2 || '%')`

        var total int64
        if err := h.db.QueryRow(ctx, `
                SELECT COUNT(*)
                FROM product_libraries l
                JOIN pharmacies ph ON ph.id = $1::uuid
                JOIN library_products lp ON lp.library_id = l.id
                JOIN global_products gp ON gp.id = lp.global_product_id
                LEFT JOIN pharmacy_products pp ON pp.pharmacy_id = $1::uuid AND pp.global_product_id = lp.global_product_id
                WHERE l.id = $3::uuid AND `+libraryVisibilityWhere+where,
                pharmacyID, search, c.Param("id"),
        ).Scan(&total); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_products_count_failed"})
                return
        }

        rows, err := h.db.Query(ctx, `
                SELECT gp.id::text, gp.name, COALESCE(gp.generic_name, ''), COALESCE(gp.brand_name, ''),
                       COALESCE(gp.barcode, ''), COALESCE(gp.strength, ''), gp.dosage_form::text,
                       gp.is_verified, lp.official_price_piastres,
                       pp.id::text, pp.selling_price,
                       (pp.id IS NOT NULL) AS already_have
                FROM product_libraries l
                JOIN pharmacies ph ON ph.id = $1::uuid
                JOIN library_products lp ON lp.library_id = l.id
                JOIN global_products gp ON gp.id = lp.global_product_id
                LEFT JOIN pharmacy_products pp ON pp.pharmacy_id = $1::uuid AND pp.global_product_id = lp.global_product_id
                WHERE l.id = $3::uuid AND `+libraryVisibilityWhere+where+`
                ORDER BY gp.name
                LIMIT $4 OFFSET $5
        `, pharmacyID, search, c.Param("id"), pageSize, (page-1)*pageSize)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_products_query_failed"})
                return
        }
        defer rows.Close()

        type prodItem struct {
                GlobalProductID string `json:"global_product_id"`
                Name            string `json:"name"`
                GenericName     string `json:"generic_name"`
                BrandName       string `json:"brand_name"`
                Barcode         string `json:"barcode"`
                Strength        string `json:"strength"`
                DosageForm      string `json:"dosage_form"`
                IsVerified      bool   `json:"is_verified"`
                OfficialPrice   int64  `json:"official_price_piastres"`
                PharmacyProductID *string `json:"pharmacy_product_id"`
                MyPrice         *int64 `json:"my_price_piastres"`
                AlreadyHave     bool   `json:"already_have"`
        }
        items := []prodItem{}
        for rows.Next() {
                var r prodItem
                if err := rows.Scan(&r.GlobalProductID, &r.Name, &r.GenericName, &r.BrandName,
                        &r.Barcode, &r.Strength, &r.DosageForm, &r.IsVerified, &r.OfficialPrice,
                        &r.PharmacyProductID, &r.MyPrice, &r.AlreadyHave); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_products_scan_failed"})
                        return
                }
                items = append(items, r)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_products_scan_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{
                "data": items,
                "pagination": gin.H{
                        "total": total, "page": page, "page_size": pageSize,
                        "total_pages": (total + int64(pageSize) - 1) / int64(pageSize),
                },
        })
}

// GetPharmacyLibraryDiff — GET /pharmacy/libraries/:id/diff
// «ما الجديد منذ آخر مزامنة لي؟» — the exact rows the pull will read.
// Never imported → sync_version 0 and empty list (the UI offers the
// import wizard instead).
func (h *Handler) GetPharmacyLibraryDiff(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        ctx := c.Request.Context()

        var libraryID, name string
        var version, lastSynced int
        var isPublished bool
        err := h.db.QueryRow(ctx, `
                SELECT l.id::text, l.name, l.version, l.is_published, COALESCE(s.last_synced_version, 0)
                FROM product_libraries l
                JOIN pharmacies ph ON ph.id = $1::uuid
                LEFT JOIN pharmacy_library_syncs s ON s.library_id = l.id AND s.pharmacy_id = $1::uuid
                WHERE l.id = $2::uuid AND `+libraryVisibilityWhere+`
        `, pharmacyID, c.Param("id")).Scan(&libraryID, &name, &version, &isPublished, &lastSynced)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_visible", "message": "المكتبة غير متاحة لهذه الصيدلية"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_diff_failed"})
                return
        }

        type changeRow struct {
                GlobalProductID string `json:"global_product_id"`
                ProductName     string `json:"product_name"`
                Barcode         string `json:"barcode"`
                Version         int    `json:"version"`
                ChangeType      string `json:"change_type"`
                OldPrice        *int64 `json:"old_price_piastres"`
                NewPrice        *int64 `json:"new_price_piastres"`
                Summary         string `json:"summary"`
                CreatedAt       time.Time `json:"created_at"`
        }
        rows, err := h.db.Query(ctx, `
                SELECT DISTINCT ON (c.global_product_id, c.change_type)
                       c.global_product_id::text, gp.name, COALESCE(gp.barcode, ''),
                       c.version, c.change_type, c.old_price_piastres, c.new_price_piastres,
                       COALESCE(c.summary, ''), c.created_at
                FROM library_changes c
                JOIN global_products gp ON gp.id = c.global_product_id
                WHERE c.library_id = $1::uuid
                  AND c.version > $2 AND c.version <= $3
                ORDER BY c.global_product_id, c.change_type, c.version DESC, c.created_at DESC
        `, libraryID, lastSynced, version)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_diff_failed"})
                return
        }
        defer rows.Close()

        changes := []changeRow{}
        counts := map[string]int{}
        for rows.Next() {
                var r changeRow
                if err := rows.Scan(&r.GlobalProductID, &r.ProductName, &r.Barcode, &r.Version,
                        &r.ChangeType, &r.OldPrice, &r.NewPrice, &r.Summary, &r.CreatedAt); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_diff_failed"})
                        return
                }
                counts[r.ChangeType]++
                changes = append(changes, r)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_diff_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "library": gin.H{"id": libraryID, "name": name, "version": version,
                        "last_synced_version": lastSynced, "is_published": isPublished},
                "changes": changes,
                "counts":  counts,
        }})
}

// ---------------------------------------------------------------------------
// البوابة 2 — كشف التكرار مقابل منتجات الصيدلية (دفعة واحدة)
// ---------------------------------------------------------------------------

// libraryCandidate — منتج من المكتبة مرشّح للاستيراد.
type libraryCandidate struct {
        GlobalProductID string  `json:"global_product_id"`
        Name            string  `json:"name"`
        Barcode         string  `json:"barcode"`
        OfficialPrice   int64   `json:"official_price_piastres"`
        AlreadyHave     bool    `json:"already_have"`
        PharmacyProductID string  `json:"pharmacy_product_id,omitempty"`
        MyPrice         *int64  `json:"my_price_piastres,omitempty"`
        SuggestedAction string  `json:"suggested_action"` // create_new | link_existing | already_have
        Matches         []matchCandidate `json:"matches,omitempty"`
        PlanLimited     bool    `json:"plan_limited,omitempty"`
}

// matchCandidate — منتج قائم بالصيدلية يشتبه بأنه نفس المنتج.
type matchCandidate struct {
        PharmacyProductID string  `json:"pharmacy_product_id"`
        Name              string  `json:"name"`
        Barcode           string  `json:"barcode"`
        Price             int64   `json:"selling_price_piastres"`
        Score             float64 `json:"score"`
        MatchType         string  `json:"match_type"` // global_match | barcode | name
}

// loadLibraryCandidates returns the library's current published products as
// import candidates (optionally restricted to selected global product ids:
// non-empty filter = explicit selection).
func (h *Handler) loadLibraryCandidates(ctx context.Context, pharmacyID, libraryID string, filter map[string]bool) ([]libraryCandidate, error) {
        rows, err := h.db.Query(ctx, `
                SELECT lp.global_product_id::text, gp.name, COALESCE(gp.barcode, ''),
                       lp.official_price_piastres,
                       pp.id::text, pp.selling_price
                FROM product_libraries l
                JOIN pharmacies ph ON ph.id = $1::uuid
                JOIN library_products lp ON lp.library_id = l.id
                JOIN global_products gp ON gp.id = lp.global_product_id
                LEFT JOIN pharmacy_products pp ON pp.pharmacy_id = $1::uuid AND pp.global_product_id = lp.global_product_id
                WHERE l.id = $2::uuid AND `+libraryVisibilityWhere+`
                ORDER BY gp.name
        `, pharmacyID, libraryID)
        if err != nil {
                return nil, err
        }
        defer rows.Close()

        candidates := []libraryCandidate{}
        for rows.Next() {
                var r libraryCandidate
                var ppID *string
                var myPrice *int64
                if err := rows.Scan(&r.GlobalProductID, &r.Name, &r.Barcode, &r.OfficialPrice, &ppID, &myPrice); err != nil {
                        return nil, err
                }
                if filter != nil && !filter[r.GlobalProductID] {
                        continue
                }
                r.AlreadyHave = ppID != nil
                r.PharmacyProductID = derefStr(ppID)
                r.MyPrice = myPrice
                if r.AlreadyHave {
                        r.SuggestedAction = "already_have"
                } else {
                        r.SuggestedAction = "create_new"
                }
                candidates = append(candidates, r)
        }
        return candidates, rows.Err()
}

// attachDedupMatches fills each not-yet-had candidate with the pharmacy's
// possible existing twins — one batched query for the whole selection.
func (h *Handler) attachDedupMatches(ctx context.Context, pharmacyID string, candidates []libraryCandidate, minScore float64) error {
        ids := make([]string, 0, len(candidates))
        for i := range candidates {
                if !candidates[i].AlreadyHave {
                        ids = append(ids, candidates[i].GlobalProductID)
                }
        }
        if len(ids) == 0 {
                return nil
        }

        rows, err := h.db.Query(ctx, `
                WITH cand AS (
                        SELECT c.gpid::uuid AS gpid, gp.barcode AS cbarcode, gp.name AS cname
                        FROM unnest($2::uuid[]) AS c(gpid)
                        JOIN global_products gp ON gp.id = c.gpid
                )
                SELECT c.gpid::text, pp.id::text, pgp.name, COALESCE(pgp.barcode, ''),
                       pp.selling_price, similarity(pgp.name, c.cname),
                       CASE
                         WHEN c.cbarcode <> '' AND pgp.barcode = c.cbarcode THEN 'barcode'
                         WHEN pgp.name ILIKE '%' || c.cname || '%' OR c.cname ILIKE '%' || pgp.name || '%' THEN 'name_contains'
                         ELSE 'name'
                       END
                FROM cand c
                JOIN pharmacy_products pp ON pp.pharmacy_id = $1::uuid AND pp.is_active
                JOIN global_products pgp ON pgp.id = pp.global_product_id
                WHERE (c.cbarcode <> '' AND pgp.barcode = c.cbarcode)
                   OR pgp.name ILIKE '%' || c.cname || '%' OR c.cname ILIKE '%' || pgp.name || '%'
                   OR similarity(pgp.name, c.cname) >= $3
        `, pharmacyID, ids, minScore)
        if err != nil {
                return err
        }
        defer rows.Close()

        byCandidate := make(map[string][]matchCandidate)
        for rows.Next() {
                var gpid, ppID, ppName, ppBarcode, matchType string
                var price int64
                var score float64
                if err := rows.Scan(&gpid, &ppID, &ppName, &ppBarcode, &price, &score, &matchType); err != nil {
                        return err
                }
                byCandidate[gpid] = append(byCandidate[gpid], matchCandidate{
                        PharmacyProductID: ppID, Name: ppName, Barcode: ppBarcode,
                        Price: price, Score: score, MatchType: matchType,
                })
        }
        if err := rows.Err(); err != nil {
                return err
        }
        for i := range candidates {
                if ms, ok := byCandidate[candidates[i].GlobalProductID]; ok {
                        candidates[i].Matches = ms
                        // اقتراح الربط عند تطابق باركود قاطع أو احتواء اسم واضح أو تشابه قوي.
                        for _, m := range ms {
                                if m.MatchType == "barcode" || m.MatchType == "name_contains" || m.Score >= nameAutoLinkThreshold {
                                        candidates[i].SuggestedAction = "link_existing"
                                        break
                                }
                        }
                }
        }
        return nil
}

// applyPlanLimitToCandidates — البوابة 3: سقف خطة المنتجات. العناصر التي
// ستنشئ صفوفًا جديدة تُحتسب بالترتيب؛ ما تجاوز السقف يُوسم plan_limited.
func (h *Handler) applyPlanLimitToCandidates(c *gin.Context, pharmacyID string, candidates []libraryCandidate) (used, limit int, err error) {
        if h.subs == nil {
                return 0, -1, nil
        }
        principal, _ := auth.PrincipalFromContext(c)
        companyID := h.companyIDForGate(c, principal)
        if companyID == "" {
                return 0, -1, nil
        }
        used, limit, _, err = h.subs.CheckLimit(c.Request.Context(), companyID, models.LimitKeyProducts)
        if err != nil {
                return 0, 0, err
        }
        remaining := limit // -1 = unlimited, 0 = not configured → treated unlimited
        unlimited := limit == -1 || limit == 0
        if !unlimited {
                remaining = limit - used
                if remaining < 0 {
                        remaining = 0
                }
        }
        for i := range candidates {
                if candidates[i].AlreadyHave {
                        continue // تحديث سعر منتج قائم لا يستهلك السقف
                }
                if unlimited {
                        continue
                }
                if remaining <= 0 {
                        candidates[i].PlanLimited = true
                        if candidates[i].SuggestedAction == "create_new" || candidates[i].SuggestedAction == "link_existing" {
                                candidates[i].SuggestedAction = "plan_limited"
                        }
                        continue
                }
                if candidates[i].SuggestedAction == "create_new" {
                        remaining--
                }
        }
        return used, limit, nil
}

func derefStr(s *string) string {
        if s == nil {
                return ""
        }
        return *s
}

// ---------------------------------------------------------------------------
// المعاينة والتنفيذ (البوابات الثلاث)
// ---------------------------------------------------------------------------

// PreviewPharmacyLibraryImport — POST /pharmacy/libraries/:id/import/preview
// body: {mode: 'all'|'selected', global_product_ids?: string[]}
func (h *Handler) PreviewPharmacyLibraryImport(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        var payload struct {
                Mode             string   `json:"mode"`
                GlobalProductIDs []string `json:"global_product_ids"`
        }
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        var filter map[string]bool
        if strings.TrimSpace(payload.Mode) == "selected" || len(payload.GlobalProductIDs) > 0 {
                filter = make(map[string]bool, len(payload.GlobalProductIDs))
                for _, id := range payload.GlobalProductIDs {
                        filter[strings.TrimSpace(id)] = true
                }
                if len(filter) == 0 {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "empty_selection", "message": "لم يتم تحديد أي منتج"})
                        return
                }
        }

        ctx := c.Request.Context()
        candidates, err := h.loadLibraryCandidates(ctx, pharmacyID, c.Param("id"), filter)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_preview_failed"})
                return
        }
        if len(candidates) == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_visible", "message": "المكتبة غير متاحة أو لا منتجات مطابقة"})
                return
        }

        if err := h.attachDedupMatches(ctx, pharmacyID, candidates, nameSuspectThreshold); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_preview_failed"})
                return
        }
        used, limit, err := h.applyPlanLimitToCandidates(c, pharmacyID, candidates)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_preview_failed"})
                return
        }

        summary := map[string]int{}
        for _, cand := range candidates {
                summary[cand.SuggestedAction]++
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "candidates": candidates,
                "summary":    summary,
                "plan":       gin.H{"products_used": used, "products_limit": limit},
        }})
}

// ExecutePharmacyLibraryImport — POST /pharmacy/libraries/:id/import/execute
// body: {items: [{global_product_id, action: 'create'|'link',
//                 pharmacy_product_id?: string}]}
// Everything is re-validated server-side: link targets must belong to this
// pharmacy, «create» converts to a price update when the product already
// exists, and the plan limit is enforced for real inserts (skips, not
// failures). The sync pointer moves to the library's current version.
func (h *Handler) ExecutePharmacyLibraryImport(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        var payload struct {
                Items []struct {
                        GlobalProductID   string  `json:"global_product_id"`
                        Action            string  `json:"action"`
                        PharmacyProductID *string `json:"pharmacy_product_id"`
                } `json:"items"`
        }
        if err := c.ShouldBindJSON(&payload); err != nil || len(payload.Items) == 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "حدد منتجًا واحدًا على الأقل"})
                return
        }

        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)

        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        // قفل المكتبة والتحقق من الرؤية داخل المعاملة.
        var libraryVersion int
        err = tx.QueryRow(ctx, `
                SELECT l.version
                FROM product_libraries l
                JOIN pharmacies ph ON ph.id = $1::uuid
                WHERE l.id = $2::uuid AND `+libraryVisibilityWhere+`
                FOR UPDATE OF l
        `, pharmacyID, c.Param("id")).Scan(&libraryVersion)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_visible", "message": "المكتبة غير متاحة لهذه الصيدلية"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                return
        }

        // الأسعار الرسمية للعناصر المطلوبة (من الإصدار المنشور فقط).
        want := make(map[string]struct {
                action string
                ppID   *string
        }, len(payload.Items))
        order := make([]string, 0, len(payload.Items))
        for _, it := range payload.Items {
                id := strings.TrimSpace(it.GlobalProductID)
                if id == "" {
                        continue
                }
                if _, seen := want[id]; !seen {
                        order = append(order, id)
                }
                action := it.Action
                if action != "create" && action != "link" {
                        action = "create"
                }
                want[id] = struct {
                        action string
                        ppID   *string
                }{action, it.PharmacyProductID}
        }
        if len(want) == 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "حدد منتجًا واحدًا على الأقل"})
                return
        }

        type official struct {
                price    int64
                name     string
                gpExists bool
        }
        officials := make(map[string]official, len(order))
        rows, err := tx.Query(ctx, `
                SELECT lp.global_product_id::text, lp.official_price_piastres, gp.name
                FROM library_products lp
                JOIN global_products gp ON gp.id = lp.global_product_id
                WHERE lp.library_id = $1::uuid AND lp.global_product_id::text = ANY($2)
        `, c.Param("id"), order)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                return
        }
        for rows.Next() {
                var id string
                var o official
                if err := rows.Scan(&id, &o.price, &o.name); err != nil {
                        rows.Close()
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                        return
                }
                o.gpExists = true
                officials[id] = o
        }
        rows.Close()
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                return
        }

        // البوابة 3 (تنفيذية): سقف الخطة على الصفوف الجديدة فعليًا.
        planUsed, planLimit := 0, -1
        if h.subs != nil {
                companyID := h.companyIDForGate(c, principal)
                if companyID != "" {
                        if used, limit, _, lerr := h.subs.CheckLimit(ctx, companyID, models.LimitKeyProducts); lerr == nil {
                                planUsed, planLimit = used, limit
                        }
                }
        }
        remaining := planLimit
        unlimited := planLimit == -1 || planLimit == 0
        if !unlimited {
                remaining = planLimit - planUsed
                if remaining < 0 {
                        remaining = 0
                }
        }

        applied, priceUpdated, linked, created := 0, 0, 0, 0
        skipped := []gin.H{}
        affected := make([]string, 0, len(order))

        for _, gpID := range order {
                o, inLibrary := officials[gpID]
                if !inLibrary {
                        skipped = append(skipped, gin.H{"global_product_id": gpID, "reason": "not_in_library"})
                        continue
                }
                decision := want[gpID]

                // هل لدى الصيدلية صف موجود بالفعل لهذا المنتج؟ (المصدر الحقيقي)
                var existingPP string
                var existingPrice int64
                err := tx.QueryRow(ctx, `
                        SELECT id::text, selling_price FROM pharmacy_products
                        WHERE pharmacy_id = $1::uuid AND global_product_id = $2::uuid
                `, pharmacyID, gpID).Scan(&existingPP, &existingPrice)
                exists := err == nil
                if err != nil && !errors.Is(err, pgx.ErrNoRows) {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                        return
                }

                switch {
                case exists:
                        // موجود: حدّث سعر البيع إلى الرسمي (القاعدة الحمراء: لا لمس للتكلفة أو المخزون).
                        // سعر رسمي صفر = بيانات ناقصة في المكتبة — لا نصفر سعر الصيدلية أبدًا.
                        if existingPrice != o.price && o.price > 0 {
                                if _, err := tx.Exec(ctx, `
                                        UPDATE pharmacy_products SET selling_price = $3, updated_at = NOW()
                                        WHERE id = $1::uuid AND pharmacy_id = $2::uuid
                                `, existingPP, pharmacyID, o.price); err != nil {
                                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                                        return
                                }
                                priceUpdated++
                        }
                        affected = append(affected, gpID)
                        applied++
                case decision.action == "link" && decision.ppID != nil:
                        // ربط صريح من المراجعة: الصف يجب أن يخص هذه الصيدلية فعلًا.
                        if o.price <= 0 {
                                skipped = append(skipped, gin.H{"global_product_id": gpID, "reason": "no_official_price", "product_name": o.name})
                                continue
                        }
                        tag, lerr := tx.Exec(ctx, `
                                UPDATE pharmacy_products SET global_product_id = $3::uuid, selling_price = $4, updated_at = NOW()
                                WHERE id = $1::uuid AND pharmacy_id = $2::uuid
                        `, *decision.ppID, pharmacyID, gpID, o.price)
                        if lerr != nil {
                                if isUniqueViolation(lerr) {
                                        skipped = append(skipped, gin.H{"global_product_id": gpID, "reason": "link_conflict"})
                                        continue
                                }
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                                return
                        }
                        if tag.RowsAffected() == 0 {
                                skipped = append(skipped, gin.H{"global_product_id": gpID, "reason": "link_target_invalid"})
                                continue
                        }
                        linked++
                        affected = append(affected, gpID)
                        applied++
                default:
                        // إنشاء جديد — يخضع لسقف الخطة، ولا يُقبل بلا سعر رسمي
                        // (استيراد منتجات مجهولة السعر يضر الصيدلية).
                        if o.price <= 0 {
                                skipped = append(skipped, gin.H{"global_product_id": gpID, "reason": "no_official_price", "product_name": o.name})
                                continue
                        }
                        if !unlimited {
                                if remaining <= 0 {
                                        skipped = append(skipped, gin.H{"global_product_id": gpID,
                                                "reason": "plan_limit", "product_name": o.name})
                                        continue
                                }
                                remaining--
                        }
                        if _, err := tx.Exec(ctx, `
                                INSERT INTO pharmacy_products (pharmacy_id, global_product_id, selling_price, cost_price, min_stock_level)
                                VALUES ($1::uuid, $2::uuid, $3, 0, 0)
                                ON CONFLICT (pharmacy_id, global_product_id) DO NOTHING
                        `, pharmacyID, gpID, o.price); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                                return
                        }
                        created++
                        affected = append(affected, gpID)
                        applied++
                }
        }

        // تحديث مؤشر المزامنة إلى الإصدار الحالي (إن كان أقدم).
        if _, err := tx.Exec(ctx, `
                INSERT INTO pharmacy_library_syncs (pharmacy_id, library_id, last_synced_version, synced_at)
                VALUES ($1::uuid, $2::uuid, $3, NOW())
                ON CONFLICT (pharmacy_id, library_id) DO UPDATE SET
                        last_synced_version = GREATEST(pharmacy_library_syncs.last_synced_version, EXCLUDED.last_synced_version),
                        synced_at = NOW()
        `, pharmacyID, c.Param("id"), libraryVersion); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                return
        }

        if err := writeAuditLog(ctx, tx, principal, "libraries.import", "import",
                "product_library", c.Param("id"),
                map[string]any{"library_version": libraryVersion, "created": created,
                        "linked": linked, "price_updated": priceUpdated, "skipped": len(skipped)},
                "استيراد من مكتبة منتجات"); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_import_failed"})
                return
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "library_version": libraryVersion,
                "applied":         applied,
                "products_created": created,
                "products_linked": linked,
                "prices_updated":  priceUpdated,
                "skipped":         skipped,
                "plan":            gin.H{"products_used": planUsed, "products_limit": planLimit},
        }})
}

// SyncPharmacyLibrary — POST /pharmacy/libraries/:id/sync
// «اسحب التحديثات» — applies everything since the pharmacy's last synced
// version: official prices onto products the pharmacy already owns (cost &
// stock untouched), barcode/strong-name linking for new products (never a
// duplicate when a confident twin exists), plan-limited creations skip with
// a flag, and «removed» rows are informational only. Pointer moves to the
// library's current version.
func (h *Handler) SyncPharmacyLibrary(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)

        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        var version, lastSynced int
        err = tx.QueryRow(ctx, `
                SELECT l.version, COALESCE(s.last_synced_version, 0)
                FROM product_libraries l
                JOIN pharmacies ph ON ph.id = $1::uuid
                LEFT JOIN pharmacy_library_syncs s ON s.library_id = l.id AND s.pharmacy_id = $1::uuid
                WHERE l.id = $2::uuid AND `+libraryVisibilityWhere+`
                FOR UPDATE OF l
        `, pharmacyID, c.Param("id")).Scan(&version, &lastSynced)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_visible", "message": "المكتبة غير متاحة لهذه الصيدلية"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                return
        }
        if lastSynced == 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "library_not_imported", "message": "استورد المكتبة أولًا قبل سحب التحديثات"})
                return
        }
        if lastSynced >= version {
                c.JSON(http.StatusOK, gin.H{"data": gin.H{
                        "synced": true, "library_version": version, "last_synced_version": lastSynced,
                        "nothing_to_do": true,
                        "prices_updated": 0, "products_added": 0, "products_linked": 0, "skipped": []gin.H{},
                }})
                return
        }

        // التغييرات منذ آخر مزامنة + السعر الرسمي الحالي لكل منتج.
        type libChange struct {
                gpID       string
                changeType string
                price      int64
                name       string
                barcode    string
        }
        var changes []libChange
        rows, err := tx.Query(ctx, `
                SELECT DISTINCT ON (c.global_product_id)
                       c.global_product_id::text, c.change_type,
                       COALESCE(lp.official_price_piastres, 0), gp.name, COALESCE(gp.barcode, '')
                FROM library_changes c
                JOIN global_products gp ON gp.id = c.global_product_id
                LEFT JOIN library_products lp ON lp.library_id = c.library_id AND lp.global_product_id = c.global_product_id
                WHERE c.library_id = $1::uuid AND c.version > $2 AND c.version <= $3
                ORDER BY c.global_product_id, c.version DESC, c.created_at DESC
        `, c.Param("id"), lastSynced, version)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                return
        }
        for rows.Next() {
                var ch libChange
                if err := rows.Scan(&ch.gpID, &ch.changeType, &ch.price, &ch.name, &ch.barcode); err != nil {
                        rows.Close()
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                        return
                }
                changes = append(changes, ch)
        }
        rows.Close()
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                return
        }

        planUsed, planLimit := 0, -1
        if h.subs != nil {
                companyID := h.companyIDForGate(c, principal)
                if companyID != "" {
                        if used, limit, _, lerr := h.subs.CheckLimit(ctx, companyID, models.LimitKeyProducts); lerr == nil {
                                planUsed, planLimit = used, limit
                        }
                }
        }
        remaining := planLimit
        unlimited := planLimit == -1 || planLimit == 0
        if !unlimited {
                remaining = planLimit - planUsed
                if remaining < 0 {
                        remaining = 0
                }
        }

        pricesUpdated, productsAdded, productsLinked := 0, 0, 0
        skipped := []gin.H{}
        removedInfo := []gin.H{}

        for _, ch := range changes {
                // الحالة الحالية عند الصيدلية.
                var ppID string
                var ppPrice int64
                err := tx.QueryRow(ctx, `
                        SELECT id::text, selling_price FROM pharmacy_products
                        WHERE pharmacy_id = $1::uuid AND global_product_id = $2::uuid
                `, pharmacyID, ch.gpID).Scan(&ppID, &ppPrice)
                exists := err == nil
                if err != nil && !errors.Is(err, pgx.ErrNoRows) {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                        return
                }

                switch {
                case ch.changeType == "removed":
                        // القاعدة الحمراء: إعلام فقط — الصيدلية تحتفظ بمنتجها.
                        removedInfo = append(removedInfo, gin.H{"global_product_id": ch.gpID, "name": ch.name})
                        continue
                case exists:
                        // سعر رسمي صفر = بيانات ناقصة — لا نصفر سعر الصيدلية أبدًا.
                        if ppPrice != ch.price && ch.price > 0 {
                                if _, err := tx.Exec(ctx, `
                                        UPDATE pharmacy_products SET selling_price = $3, updated_at = NOW()
                                        WHERE id = $1::uuid AND pharmacy_id = $2::uuid
                                `, ppID, pharmacyID, ch.price); err != nil {
                                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                                        return
                                }
                                pricesUpdated++
                        }
                case ch.changeType == "price_changed" || ch.changeType == "metadata_changed":
                        // السعر تغيّر لكن الصيدلية لا تملك المنتج — لا شيء يُطبق الآن
                        // (يظهر كمنتج متاح للاستيراد من صفحة المكتبة).
                        continue
                default:
                        // added: مطلوب عند الصيدلية. اربط بتوأم واثق أولًا (باركود أو
                        // اسم قوي)، وإلا أنشئ صفًا جديدًا تحت سقف الخطة.
                        var twinID string
                        var twinPrice int64
                        err := tx.QueryRow(ctx, `
                                SELECT pp.id::text, pp.selling_price
                                FROM pharmacy_products pp
                                JOIN global_products pgp ON pgp.id = pp.global_product_id
                                WHERE pp.pharmacy_id = $1::uuid AND pp.is_active
                                  AND (($3 <> '' AND pgp.barcode = $3)
                                       OR similarity(pgp.name, $2) >= $4)
                                ORDER BY (CASE WHEN $3 <> '' AND pgp.barcode = $3 THEN 0 ELSE 1 END),
                                         similarity(pgp.name, $2) DESC
                                LIMIT 1
                        `, pharmacyID, ch.name, ch.barcode, nameAutoLinkThreshold).Scan(&twinID, &twinPrice)
                        hasTwin := err == nil
                        if err != nil && !errors.Is(err, pgx.ErrNoRows) {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                                return
                        }
                        if hasTwin && ch.price > 0 {
                                if _, err := tx.Exec(ctx, `
                                        UPDATE pharmacy_products SET global_product_id = $3::uuid, selling_price = $4, updated_at = NOW()
                                        WHERE id = $1::uuid AND pharmacy_id = $2::uuid
                                `, twinID, pharmacyID, ch.gpID, ch.price); err != nil {
                                        c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                                        return
                                }
                                productsLinked++
                                continue
                        }
                        if ch.price <= 0 {
                                skipped = append(skipped, gin.H{"global_product_id": ch.gpID,
                                        "reason": "no_official_price", "product_name": ch.name})
                                continue
                        }
                        if !unlimited {
                                if remaining <= 0 {
                                        skipped = append(skipped, gin.H{"global_product_id": ch.gpID,
                                                "reason": "plan_limit", "product_name": ch.name})
                                        continue
                                }
                                remaining--
                        }
                        if _, err := tx.Exec(ctx, `
                                INSERT INTO pharmacy_products (pharmacy_id, global_product_id, selling_price, cost_price, min_stock_level)
                                VALUES ($1::uuid, $2::uuid, $3, 0, 0)
                                ON CONFLICT (pharmacy_id, global_product_id) DO NOTHING
                        `, pharmacyID, ch.gpID, ch.price); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                                return
                        }
                        productsAdded++
                }
        }

        if _, err := tx.Exec(ctx, `
                UPDATE pharmacy_library_syncs SET last_synced_version = $3, synced_at = NOW()
                WHERE pharmacy_id = $1::uuid AND library_id = $2::uuid
        `, pharmacyID, c.Param("id"), version); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                return
        }

        if err := writeAuditLog(ctx, tx, principal, "libraries.sync", "update",
                "product_library", c.Param("id"),
                map[string]any{"from_version": lastSynced, "to_version": version,
                        "prices_updated": pricesUpdated, "products_added": productsAdded,
                        "products_linked": productsLinked, "skipped": len(skipped), "removed": len(removedInfo)},
                "سحب تحديثات مكتبة منتجات"); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pharmacy_library_sync_failed"})
                return
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "synced": true, "library_version": version, "last_synced_version": lastSynced,
                "nothing_to_do": false,
                "prices_updated":  pricesUpdated,
                "products_added":  productsAdded,
                "products_linked": productsLinked,
                "skipped":         skipped,
                "removed":         removedInfo,
                "plan":            gin.H{"products_used": planUsed, "products_limit": planLimit},
        }})
}
