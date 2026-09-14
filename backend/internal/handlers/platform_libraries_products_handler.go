// Platform-admin central product libraries — library products + catalog.
//
// This file covers the library ENTRY surface (official price per product),
// the Excel bulk import that feeds a library (thousands of rows, preview →
// execute like the proven pharmacy import), and the catalog browser/editor
// used to pick existing global_products or create verified ones from
// scratch.
//
// House rules honored here:
//   - the OFFICIAL price lives on library_products (per library/currency),
//     never on global_products,
//   - every catalog/price mutation appends library_changes tagged with the
//     draft version (see platform_libraries_handler.go for the semantics),
//   - every write is audited to platform_audit_logs,
//   - import price values are major units ×100 (piastres); currencies with
//     3 decimals (KWD/BHD/OMR/JOD) need their own divisor before those
//     libraries go live — Phase 1 activates EGP only.
package handlers

import (
        "context"
        "encoding/json"
        "errors"
        "fmt"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/pharmacy-os/backend/internal/auth"
)

// ifManufacturer — حقل إضافي خاص بمكتبات المنصة (الشركة المنتجة) يُدمج مع
// مرادفات الاستيراد المشتركة من product_import_handler.go.
const ifManufacturer = "manufacturer"

// libraryImportFieldOrder — ترتيب الحقول المعروضة في معالج الربط بالواجهة.
var libraryImportFieldOrder = []string{
        ifName, ifBarcode, ifSellingPrice, ifGenericName, ifStrength,
        ifDosageForm, ifManufacturer,
}

var libraryImportSynonymsNorm = func() map[string]string {
        m := make(map[string]string)
        for k, v := range map[string]string{
                "الشركةالمنتجة": ifManufacturer, "الشركة": ifManufacturer, "المصنع": ifManufacturer,
                "المنتج": "", // never map this here — it collides with the NAME synonym
                "manufacturer": ifManufacturer, "company": ifManufacturer, "producer": ifManufacturer,
                "manufacturercountry": "manufacturer_country",
                "بلدالمنشأ":           "manufacturer_country", "بلدالمنشا": "manufacturer_country",
        } {
                if v == "" {
                        continue
                }
                m[normalizeHeaderKey(k)] = v
        }
        return m
}()

// suggestLibraryImportMapping — يقترح الربط انطلاقًا من المرادفات المشتركة
// ثم يضيف حقول المكتبة الخاصة (الشركة المنتجة).
func suggestLibraryImportMapping(headers []string) map[string]int {
        mapping := suggestImportMapping(headers)
        for i, h := range headers {
                if v, ok := libraryImportSynonymsNorm[normalizeHeaderKey(h)]; ok {
                        if _, taken := mapping[v]; !taken {
                                mapping[v] = i
                        }
                }
        }
        return mapping
}

// libraryImportRow — صف استيراد مكتبة بعد التحويل.
type libraryImportRow struct {
        Name             string
        Barcode          string
        PricePiastres    int64
        HasPrice         bool
        GenericName      string
        Strength         string
        DosageForm       string
        ManufacturerName string
}

// validateLibraryImportRow — يتحقق من صف خام ويعيد الصف المحوَّل أو سبب الرفض بالعربية.
func validateLibraryImportRow(row []string, mapping map[string]int) (libraryImportRow, string) {
        name := cell(row, mapping[ifName])
        if name == "" {
                return libraryImportRow{}, "الاسم مطلوب"
        }
        r := libraryImportRow{
                Name:             name,
                Barcode:          cell(row, mapping[ifBarcode]),
                GenericName:      cell(row, mapping[ifGenericName]),
                Strength:         cell(row, mapping[ifStrength]),
                DosageForm:       mapImportDosageForm(cell(row, mapping[ifDosageForm])),
                ManufacturerName: cell(row, mapping[ifManufacturer]),
        }
        if raw := cell(row, mapping[ifSellingPrice]); raw != "" {
                v, ok := parseArabicNumber(raw)
                if !ok || v < 0 {
                        return libraryImportRow{}, fmt.Sprintf("سعر غير مفهوم: %s", raw)
                }
                r.PricePiastres = egpToPiastres(v)
                r.HasPrice = true
        }
        return r, ""
}

// ---------------------------------------------------------------------------
// Library products (the entry surface)
// ---------------------------------------------------------------------------

type libraryProductRow struct {
        ID                    string    `json:"id"`
        GlobalProductID       string    `json:"global_product_id"`
        OfficialPricePiastres int64     `json:"official_price_piastres"`
        Notes                 *string   `json:"notes"`
        Name                  string    `json:"name"`
        GenericName           *string   `json:"generic_name"`
        Strength              *string   `json:"strength"`
        DosageForm            string    `json:"dosage_form"`
        ProductCategory       string    `json:"product_category"`
        Barcode               *string   `json:"barcode"`
        ManufacturerName      *string   `json:"manufacturer_name"`
        ActiveIngredient      *string   `json:"active_ingredient"`
        RequiresPrescription  string    `json:"requires_prescription"`
        IsVerified            bool      `json:"is_verified"`
        UpdatedAt             time.Time `json:"updated_at"`
}

const libraryProductSelectBody = `
        SELECT lp.id::text, lp.global_product_id::text, lp.official_price_piastres, lp.notes,
               gp.name, gp.generic_name, gp.strength, gp.dosage_form::text, gp.product_category::text,
               gp.barcode, gp.manufacturer_name, gp.active_ingredient, gp.requires_prescription::text,
               gp.is_verified, lp.updated_at
        FROM library_products lp
        JOIN global_products gp ON gp.id = lp.global_product_id
        WHERE lp.library_id = $1::uuid
`

// ListPlatformLibraryProducts — GET /platform-admin/libraries/:id/products?search=&page=&page_size=
func (h *Handler) ListPlatformLibraryProducts(c *gin.Context) {
        page := parsePositiveInt(c.Query("page"), 1)
        pageSize := parsePositiveInt(c.Query("page_size"), 20)
        if pageSize > 100 {
                pageSize = 100
        }
        search := strings.TrimSpace(c.Query("search"))
        ctx := c.Request.Context()

        // Stable placeholder positions: $1 library, $2 search (empty = match all)
        // and, for the page query only, $3 page size + $4 offset. Count and page
        // get their own slices: Postgres rejects parameters a statement never
        // references ("could not determine data type of parameter").
        where := ` AND ($2 = '' OR gp.name ILIKE '%' || $2 || '%' OR gp.generic_name ILIKE '%' || $2 || '%' OR gp.barcode ILIKE $2 || '%')`
        searchArg := escapeLike(search)

        var total int64
        if err := h.db.QueryRow(ctx,
                `SELECT COUNT(*) FROM library_products lp JOIN global_products gp ON gp.id = lp.global_product_id WHERE lp.library_id = $1::uuid`+where,
                c.Param("id"), searchArg,
        ).Scan(&total); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_products_count_failed"})
                return
        }

        rows, err := h.db.Query(ctx, libraryProductSelectBody+where+`
                ORDER BY gp.name LIMIT $3 OFFSET $4`,
                c.Param("id"), searchArg, pageSize, (page-1)*pageSize,
        )
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_products_query_failed"})
                return
        }
        defer rows.Close()

        items := []libraryProductRow{}
        for rows.Next() {
                var r libraryProductRow
                if err := rows.Scan(&r.ID, &r.GlobalProductID, &r.OfficialPricePiastres, &r.Notes,
                        &r.Name, &r.GenericName, &r.Strength, &r.DosageForm, &r.ProductCategory,
                        &r.Barcode, &r.ManufacturerName, &r.ActiveIngredient, &r.RequiresPrescription,
                        &r.IsVerified, &r.UpdatedAt); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "library_products_scan_failed"})
                        return
                }
                items = append(items, r)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_products_scan_failed"})
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

// upsertLibraryEntry adds the product to the library or updates its official
// price, appending the right change-log rows. Returns what happened.
func upsertLibraryEntry(ctx context.Context, tx pgx.Tx, libraryID, gpID string, pricePiastres int64, hasPrice bool, notes *string, draftVersion int) (action string, err error) {
        var (
                entryID     string
                currentP    int64
        )
        err = tx.QueryRow(ctx, `
                SELECT id::text, official_price_piastres FROM library_products
                WHERE library_id = $1::uuid AND global_product_id = $2::uuid FOR UPDATE
        `, libraryID, gpID).Scan(&entryID, &currentP)
        if errors.Is(err, pgx.ErrNoRows) {
                p := int64(0)
                if hasPrice {
                        p = pricePiastres
                }
                if _, err := tx.Exec(ctx, `
                        INSERT INTO library_products (library_id, global_product_id, official_price_piastres, notes)
                        VALUES ($1::uuid, $2::uuid, $3, $4)
                `, libraryID, gpID, p, notes); err != nil {
                        return "", err
                }
                if err := logLibraryChange(ctx, tx, libraryID, gpID, draftVersion, "added", nil, &p, "إضافة منتج إلى المكتبة"); err != nil {
                        return "", err
                }
                return "added", nil
        }
        if err != nil {
                return "", err
        }
        if hasPrice && pricePiastres != currentP {
                if _, err := tx.Exec(ctx,
                        `UPDATE library_products SET official_price_piastres = $3, notes = COALESCE($4, notes), updated_at = NOW() WHERE id = $1::uuid AND library_id = $2::uuid`,
                        entryID, libraryID, pricePiastres, notes); err != nil {
                        return "", err
                }
                if err := logLibraryChange(ctx, tx, libraryID, gpID, draftVersion, "price_changed",
                        &currentP, &pricePiastres, "تحديث السعر الرسمي"); err != nil {
                        return "", err
                }
                return "price_updated", nil
        }
        if notes != nil {
                if _, err := tx.Exec(ctx,
                        `UPDATE library_products SET notes = $3, updated_at = NOW() WHERE id = $1::uuid AND library_id = $2::uuid`,
                        entryID, libraryID, notes); err != nil {
                        return "", err
                }
        }
        return "unchanged", nil
}

// newCatalogProduct — إنشاء دواء جديد في الكتالوج المركزي من محرر المسؤول.
// Admin-created products are born verified: the platform is the source of
// truth for curated library content.
type newCatalogProduct struct {
        Name                 string `json:"name"`
        GenericName          string `json:"generic_name"`
        BrandName            string `json:"brand_name"`
        DosageForm           string `json:"dosage_form"`
        Strength             string `json:"strength"`
        ProductCategory      string `json:"product_category"`
        RequiresPrescription string `json:"requires_prescription"`
        Barcode              string `json:"barcode"`
        GenerateBarcode      bool   `json:"generate_barcode"`
        ManufacturerName     string `json:"manufacturer_name"`
        ManufacturerCountry  string `json:"manufacturer_country"`
        ActiveIngredient     string `json:"active_ingredient"`
        AtcCode              string `json:"atc_code"`
        TherapeuticClass     string `json:"therapeutic_class"`
        StorageInstructions  string `json:"storage_instructions"`
        Description          string `json:"description"`
}

var validDosageForms = map[string]bool{
        "tablet": true, "capsule": true, "syrup": true, "drop": true, "injection": true,
        "ointment": true, "cream": true, "gel": true, "powder": true, "solution": true,
        "suspension": true, "inhaler": true, "patch": true, "suppository": true,
        "eye_drops": true, "ear_drops": true, "nasal_spray": true, "other": true,
}

var validProductCategories = map[string]bool{
        "medication": true, "supplement": true, "medical_device": true, "personal_care": true,
        "cosmetic": true, "food_supplement": true, "herbal": true, "vaccine": true,
        "consumable": true, "other": true,
}

func (n *newCatalogProduct) normalize() {
        n.Name = strings.TrimSpace(n.Name)
        n.GenericName = strings.TrimSpace(n.GenericName)
        n.BrandName = strings.TrimSpace(n.BrandName)
        n.DosageForm = strings.TrimSpace(n.DosageForm)
        n.Strength = strings.TrimSpace(n.Strength)
        n.ProductCategory = strings.TrimSpace(n.ProductCategory)
        n.RequiresPrescription = strings.TrimSpace(n.RequiresPrescription)
        n.Barcode = strings.TrimSpace(n.Barcode)
        n.ManufacturerName = strings.TrimSpace(n.ManufacturerName)
        n.ManufacturerCountry = strings.TrimSpace(n.ManufacturerCountry)
        n.ActiveIngredient = strings.TrimSpace(n.ActiveIngredient)
        n.AtcCode = strings.TrimSpace(n.AtcCode)
        n.TherapeuticClass = strings.TrimSpace(n.TherapeuticClass)
}

func (n *newCatalogProduct) validate() string {
        if n.Name == "" {
                return "اسم المنتج مطلوب"
        }
        if n.DosageForm == "" {
                n.DosageForm = "tablet"
        }
        if !validDosageForms[n.DosageForm] {
                return "الشكل الصيدلي غير معروف"
        }
        if n.ProductCategory == "" {
                n.ProductCategory = "medication"
        }
        if !validProductCategories[n.ProductCategory] {
                return "تصنيف المنتج غير معروف"
        }
        if n.RequiresPrescription == "" {
                n.RequiresPrescription = "no"
        }
        if n.RequiresPrescription != "yes" && n.RequiresPrescription != "no" && n.RequiresPrescription != "otc_only" {
                return "قيمة وصفة الطبيب يجب أن تكون: yes أو no أو otc_only"
        }
        return ""
}

// createCatalogProduct inserts a global_products row inside the caller's tx
// (source=platform_admin, verified) with optional RCN barcode generation.
func (h *Handler) createCatalogProduct(ctx context.Context, tx pgx.Tx, p *newCatalogProduct) (string, error) {
        barcodeValue := p.Barcode
        if barcodeValue == "" && p.GenerateBarcode {
                code, err := drawInternalBarcode(ctx, tx)
                if err != nil {
                        return "", err
                }
                barcodeValue = code
        }
        var id string
        err := tx.QueryRow(ctx, `
                INSERT INTO global_products (
                        name, generic_name, brand_name, dosage_form, strength, product_category,
                        requires_prescription, barcode, manufacturer_name, manufacturer_country,
                        active_ingredient, atc_code, therapeutic_class, storage_instructions,
                        description, is_verified, source
                ) VALUES (
                        $1, NULLIF($2,''), NULLIF($3,''), $4, NULLIF($5,''), $6,
                        $7, NULLIF($8,''), NULLIF($9,''), NULLIF($10,''),
                        NULLIF($11,''), NULLIF($12,''), NULLIF($13,''), NULLIF($14,''),
                        NULLIF($15,''), true, 'platform_admin'
                )
                RETURNING id::text
        `, p.Name, p.GenericName, p.BrandName, p.DosageForm, p.Strength, p.ProductCategory,
                p.RequiresPrescription, barcodeValue, p.ManufacturerName, p.ManufacturerCountry,
                p.ActiveIngredient, p.AtcCode, p.TherapeuticClass, p.StorageInstructions,
                p.Description).Scan(&id)
        if err != nil {
                // Barcode collision: another product already owns this code. Link to
                // it instead of failing — the catalog stays deduplicated by barcode.
                if isUniqueViolation(err) && barcodeValue != "" {
                        var existing string
                        qerr := tx.QueryRow(ctx,
                                `SELECT id::text FROM global_products WHERE barcode = $1 LIMIT 1`, barcodeValue).Scan(&existing)
                        if qerr == nil {
                                return existing, nil
                        }
                }
                return "", err
        }
        return id, nil
}

// AddPlatformLibraryProduct — POST /platform-admin/libraries/:id/products
// Upsert semantics: adding an existing entry with a new price UPDATES it and
// logs price_changed — bulk price-list imports rely on this behavior.
func (h *Handler) AddPlatformLibraryProduct(c *gin.Context) {
        var payload struct {
                GlobalProductID       string             `json:"global_product_id"`
                OfficialPricePiastres *int64             `json:"official_price_piastres"`
                Notes                 *string            `json:"notes"`
                NewProduct            *newCatalogProduct `json:"new_product"`
        }
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        if payload.GlobalProductID == "" && payload.NewProduct == nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "product_source_required", "message": "حدّد منتجًا من الكتالوج أو أدخل منتجًا جديدًا"})
                return
        }
        if payload.OfficialPricePiastres != nil && *payload.OfficialPricePiastres < 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_price", "message": "السعر الرسمي لا يمكن أن يكون سالبًا"})
                return
        }
        if payload.NewProduct != nil {
                payload.NewProduct.normalize()
                if msg := payload.NewProduct.validate(); msg != "" {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_product", "message": msg})
                        return
                }
        }

        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        createdProduct := false
        gpID := payload.GlobalProductID
        if payload.NewProduct != nil {
                gpID, err = h.createCatalogProduct(ctx, tx, payload.NewProduct)
                if err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_product_create_failed"})
                        return
                }
                createdProduct = true
        } else {
                var exists bool
                if err := tx.QueryRow(ctx,
                        `SELECT EXISTS (SELECT 1 FROM global_products WHERE id = $1::uuid)`, gpID).Scan(&exists); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_check_failed"})
                        return
                }
                if !exists {
                        c.JSON(http.StatusNotFound, gin.H{"error": "catalog_product_not_found", "message": "المنتج غير موجود في الكتالوج المركزي"})
                        return
                }
        }

        draftVersion, _, err := libraryDraftVersion(ctx, tx, c.Param("id"))
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_found", "message": "المكتبة غير موجودة"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_query_failed"})
                return
        }

        hasPrice := payload.OfficialPricePiastres != nil
        price := int64(0)
        if hasPrice {
                price = *payload.OfficialPricePiastres
        }
        action, err := upsertLibraryEntry(ctx, tx, c.Param("id"), gpID, price, hasPrice, payload.Notes, draftVersion)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_product_upsert_failed"})
                return
        }
        if err := touchLibrary(ctx, tx, c.Param("id")); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_touch_failed"})
                return
        }
        if err := writePlatformAuditLog(ctx, tx, principal,
                "library.product_add", "create", "library_product", c.Param("id")+"/"+gpID, "",
                map[string]any{"library_id": c.Param("id"), "global_product_id": gpID,
                        "official_price_piastres": price, "created_product": createdProduct, "action": action},
                "إضافة/تحديث منتج في مكتبة"); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "library_id":            c.Param("id"),
                "global_product_id":     gpID,
                "created_product":       createdProduct,
                "action":                action,
                "official_price_piastres": price,
        }})
}

// UpdatePlatformLibraryProduct — PUT /platform-admin/libraries/:id/products/:pid
func (h *Handler) UpdatePlatformLibraryProduct(c *gin.Context) {
        var payload struct {
                OfficialPricePiastres *int64  `json:"official_price_piastres"`
                Notes                 *string `json:"notes"`
        }
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        if payload.OfficialPricePiastres != nil && *payload.OfficialPricePiastres < 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_price", "message": "السعر الرسمي لا يمكن أن يكون سالبًا"})
                return
        }

        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        var (
                gpID     string
                currentP int64
        )
        err = tx.QueryRow(ctx, `
                SELECT lp.global_product_id::text, lp.official_price_piastres
                FROM library_products lp
                WHERE lp.id = $1::uuid AND lp.library_id = $2::uuid FOR UPDATE
        `, c.Param("pid"), c.Param("id")).Scan(&gpID, &currentP)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_product_not_found", "message": "المنتج غير موجود في هذه المكتبة"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_product_query_failed"})
                return
        }

        // Price change → update + change log; notes change → plain update.
        // COALESCE keeps whichever field the payload did not touch.
        priceChanged := payload.OfficialPricePiastres != nil && *payload.OfficialPricePiastres != currentP
        if priceChanged || payload.Notes != nil {
                if _, err := tx.Exec(ctx, `
                        UPDATE library_products
                        SET official_price_piastres = COALESCE($2, official_price_piastres),
                            notes = COALESCE($3, notes),
                            updated_at = NOW()
                        WHERE id = $1::uuid
                `, c.Param("pid"), payload.OfficialPricePiastres, payload.Notes); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "library_product_update_failed"})
                        return
                }
        }
        if priceChanged {
                draftVersion, _, err := libraryDraftVersion(ctx, tx, c.Param("id"))
                if err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "library_query_failed"})
                        return
                }
                newP := *payload.OfficialPricePiastres
                if err := logLibraryChange(ctx, tx, c.Param("id"), gpID, draftVersion, "price_changed",
                        &currentP, &newP, "تعديل يدوي للسعر الرسمي"); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "library_change_log_failed"})
                        return
                }
                if err := touchLibrary(ctx, tx, c.Param("id")); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "library_touch_failed"})
                        return
                }
        }
        if err := writePlatformAuditLog(ctx, tx, principal,
                "library.product_update", "update", "library_product", c.Param("pid"), "",
                map[string]any{"library_id": c.Param("id"), "global_product_id": gpID,
                        "old_price_piastres": currentP, "new_price_piastres": payload.OfficialPricePiastres},
                "تعديل منتج داخل مكتبة"); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"updated": true, "price_changed": priceChanged}})
}

// RemovePlatformLibraryProduct — DELETE /platform-admin/libraries/:id/products/:pid
// Removing an entry logs «removed» so pharmacies (Phase 2) see it in the
// diff; products already imported into a pharmacy stay theirs — the log is
// informational, never a deletion order.
func (h *Handler) RemovePlatformLibraryProduct(c *gin.Context) {
        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        var (
                gpID     string
                name     string
                currentP int64
        )
        err = tx.QueryRow(ctx, `
                SELECT lp.global_product_id::text, gp.name, lp.official_price_piastres
                FROM library_products lp
                JOIN global_products gp ON gp.id = lp.global_product_id
                WHERE lp.id = $1::uuid AND lp.library_id = $2::uuid FOR UPDATE OF lp
        `, c.Param("pid"), c.Param("id")).Scan(&gpID, &name, &currentP)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_product_not_found", "message": "المنتج غير موجود في هذه المكتبة"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_product_query_failed"})
                return
        }
        if _, err := tx.Exec(ctx, `DELETE FROM library_products WHERE id = $1::uuid`, c.Param("pid")); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_product_delete_failed"})
                return
        }
        draftVersion, _, err := libraryDraftVersion(ctx, tx, c.Param("id"))
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_query_failed"})
                return
        }
        if err := logLibraryChange(ctx, tx, c.Param("id"), gpID, draftVersion, "removed",
                &currentP, nil, "سحب منتج من المكتبة"); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_change_log_failed"})
                return
        }
        if err := touchLibrary(ctx, tx, c.Param("id")); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_touch_failed"})
                return
        }
        if err := writePlatformAuditLog(ctx, tx, principal,
                "library.product_remove", "delete", "library_product", c.Param("pid"), "",
                map[string]any{"library_id": c.Param("id"), "global_product_id": gpID, "product_name": name},
                "سحب منتج من مكتبة: "+name); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"removed": true}})
}

// PreviewPlatformLibraryImport — POST /platform-admin/libraries/:id/import/preview
// Same 2-step contract as the pharmacy import: parse the file, suggest the
// column mapping (accepting an override), and estimate validity — the UI
// shows the sample before the execute call commits anything.
func (h *Handler) PreviewPlatformLibraryImport(c *gin.Context) {
        fh, err := c.FormFile("file")
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "file_required", "message": "يرجى رفع ملف Excel (xlsx) أو CSV"})
                return
        }
        headers, rows, fileType, perr := parseImportFile(fh)
        if perr != nil {
                msg := map[string]string{
                        "file_too_large":     "حجم الملف أكبر من 10 ميجابايت",
                        "unsupported_format": "صيغة غير مدعومة — يُقبل Excel بصيغة xlsx أو ملف CSV",
                        "invalid_xlsx":       "الملف ليس ملف Excel صالحًا",
                        "invalid_csv":        "ملف CSV غير صالح",
                        "empty_file":         "الملف لا يحتوي بيانات",
                        "cannot_read_file":   "تعذرت قراءة الملف",
                }[perr.Error()]
                if msg == "" {
                        msg = "تعذر تحليل الملف"
                }
                c.JSON(http.StatusBadRequest, gin.H{"error": perr.Error(), "message": msg})
                return
        }
        if len(rows) > importMaxRows {
                c.JSON(http.StatusBadRequest, gin.H{"error": "too_many_rows", "message": fmt.Sprintf("الحد الأقصى %d صفًا في الملف الواحد", importMaxRows)})
                return
        }

        mapping := suggestLibraryImportMapping(headers)
        if override := strings.TrimSpace(c.PostForm("mapping")); override != "" {
                var custom map[string]int
                if err := json.Unmarshal([]byte(override), &custom); err == nil {
                        for f, idx := range custom {
                                if idx >= len(headers) {
                                        idx = -1
                                }
                                mapping[f] = idx
                        }
                }
        }

        sample := rows
        if len(sample) > importSampleRows {
                sample = sample[:importSampleRows]
        }
        valid, invalid := 0, 0
        var invalidReasons []string
        for i, r := range rows {
                if _, verr := validateLibraryImportRow(r, mapping); verr == "" {
                        valid++
                } else {
                        invalid++
                        if len(invalidReasons) < 5 {
                                invalidReasons = append(invalidReasons, fmt.Sprintf("صف %d: %s", i+2, verr))
                        }
                }
        }

        sampleOut := make([]map[string]any, 0, len(sample))
        for _, r := range sample {
                sampleOut = append(sampleOut, gin.H{
                        "name":         cell(r, mapping[ifName]),
                        "barcode":      cell(r, mapping[ifBarcode]),
                        "price":        cell(r, mapping[ifSellingPrice]),
                        "generic_name": cell(r, mapping[ifGenericName]),
                        "strength":     cell(r, mapping[ifStrength]),
                        "dosage_form":  cell(r, mapping[ifDosageForm]),
                        "manufacturer": cell(r, mapping[ifManufacturer]),
                })
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "file_type":       fileType,
                "headers":         headers,
                "mapping":         mapping,
                "fields":          libraryImportFieldOrder,
                "total_rows":      len(rows),
                "valid_rows":      valid,
                "invalid_rows":    invalid,
                "invalid_reasons": invalidReasons,
                "sample":          sampleOut,
        }})
}

// ExecutePlatformLibraryImport — POST /platform-admin/libraries/:id/import/execute
//
// Feeds a library from an Excel/CSV price list (e.g. the regulator's
// official price bulletin): rows resolve to the central catalog by barcode
// first, then by normalized name, and only truly new drugs create
// global_products rows (source=platform_admin, verified). Every library
// entry becomes an upsert: new → «added», different price →
// «price_changed» (old→new lands in the change log and later in the
// pharmacy diff). All-or-nothing in a single transaction, like the
// pharmacy import.
func (h *Handler) ExecutePlatformLibraryImport(c *gin.Context) {
        fh, err := c.FormFile("file")
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "file_required", "message": "يرجى رفع ملف Excel (xlsx) أو CSV"})
                return
        }
        headers, rows, _, perr := parseImportFile(fh)
        if perr != nil {
                msg := map[string]string{
                        "file_too_large":     "حجم الملف أكبر من 10 ميجابايت",
                        "unsupported_format": "صيغة غير مدعومة — يُقبل Excel بصيغة xlsx أو ملف CSV",
                        "invalid_xlsx":       "الملف ليس ملف Excel صالحًا",
                        "invalid_csv":        "ملف CSV غير صالح",
                        "empty_file":         "الملف لا يحتوي بيانات",
                        "cannot_read_file":   "تعذرت قراءة الملف",
                }[perr.Error()]
                if msg == "" {
                        msg = "تعذر تحليل الملف"
                }
                c.JSON(http.StatusBadRequest, gin.H{"error": perr.Error(), "message": msg})
                return
        }
        if len(rows) > importMaxRows {
                c.JSON(http.StatusBadRequest, gin.H{"error": "too_many_rows", "message": fmt.Sprintf("الحد الأقصى %d صفًا في الملف الواحد", importMaxRows)})
                return
        }

        mapping := suggestLibraryImportMapping(headers)
        if override := strings.TrimSpace(c.PostForm("mapping")); override != "" {
                var custom map[string]int
                if err := json.Unmarshal([]byte(override), &custom); err == nil {
                        for f, idx := range custom {
                                if idx >= len(headers) {
                                        idx = -1
                                }
                                mapping[f] = idx
                        }
                }
        }

        // Validate every row BEFORE opening the transaction (house rule).
        parsed := make([]libraryImportRow, 0, len(rows))
        var importErrors []string
        for i, r := range rows {
                pr, verr := validateLibraryImportRow(r, mapping)
                if verr != "" {
                        if len(importErrors) < importErrorCap {
                                importErrors = append(importErrors, fmt.Sprintf("صف %d: %s", i+2, verr))
                        }
                        continue
                }
                parsed = append(parsed, pr)
        }

        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        draftVersion, _, err := libraryDraftVersion(ctx, tx, c.Param("id"))
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "library_not_found", "message": "المكتبة غير موجودة"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_query_failed"})
                return
        }

        // Current library entries are NOT preloaded here: upsertLibraryEntry
        // takes a per-row FOR UPDATE lock, and the unique constraint backstops
        // any insert race. Fewer moving parts than a full pre-materialized map.

        // Barcode index for the whole file in ONE query.
        barcodeIdx := map[string]string{}
        {
                codes := make([]string, 0, len(parsed))
                for _, pr := range parsed {
                        if pr.Barcode != "" {
                                codes = append(codes, pr.Barcode)
                        }
                }
                if len(codes) > 0 {
                        brows, err := tx.Query(ctx,
                                `SELECT id::text, barcode FROM global_products WHERE barcode = ANY($1)`, codes)
                        if err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_barcode_query_failed"})
                                return
                        }
                        for brows.Next() {
                                var id, code string
                                if err := brows.Scan(&id, &code); err == nil {
                                        barcodeIdx[code] = id
                                }
                        }
                        brows.Close()
                }
        }

        // Name index (normalized) for rows without a barcode.
        nameIdx := map[string]string{}
        {
                nrows, err := tx.Query(ctx, `SELECT id::text, name FROM global_products`)
                if err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_name_query_failed"})
                        return
                }
                for nrows.Next() {
                        var id, name string
                        if err := nrows.Scan(&id, &name); err == nil {
                                key := normalizeImportName(name)
                                if _, taken := nameIdx[key]; !taken {
                                        nameIdx[key] = id
                                }
                        }
                }
                nrows.Close()
        }

        report := gin.H{
                "total_rows":       len(rows),
                "added":            0,
                "price_updated":    0,
                "products_created": 0,
                "unchanged":        0,
                "failed":           0,
        }
        added, priceUpdated, created, unchanged, failed := 0, 0, 0, 0, 0

        for _, pr := range parsed {
                gpID := ""
                if pr.Barcode != "" {
                        gpID = barcodeIdx[pr.Barcode]
                }
                if gpID == "" {
                        gpID = nameIdx[normalizeImportName(pr.Name)]
                }
                if gpID == "" {
                        np := newCatalogProduct{
                                Name: pr.Name, GenericName: pr.GenericName, DosageForm: pr.DosageForm,
                                Strength: pr.Strength, ProductCategory: "medication",
                                RequiresPrescription: "no", Barcode: pr.Barcode,
                                ManufacturerName: pr.ManufacturerName,
                        }
                        newID, err := h.createCatalogProduct(ctx, tx, &np)
                        if err != nil {
                                failed++
                                if len(importErrors) < importErrorCap {
                                        importErrors = append(importErrors, fmt.Sprintf("منتج %s: تعذر إنشاؤه في الكتالوج", pr.Name))
                                }
                                continue
                        }
                        gpID = newID
                        created++
                        // keep in-file dedupe consistent
                        if pr.Barcode != "" {
                                barcodeIdx[pr.Barcode] = newID
                        }
                        nameIdx[normalizeImportName(pr.Name)] = newID
                }

                action, err := upsertLibraryEntry(ctx, tx, c.Param("id"), gpID, pr.PricePiastres, pr.HasPrice, nil, draftVersion)
                if err != nil {
                        failed++
                        if len(importErrors) < importErrorCap {
                                importErrors = append(importErrors, fmt.Sprintf("منتج %s: تعذر إضافته للمكتبة", pr.Name))
                        }
                        continue
                }
                switch action {
                case "added":
                        added++
                case "price_updated":
                        priceUpdated++
                default:
                        unchanged++
                }
        }

        if err := touchLibrary(ctx, tx, c.Param("id")); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_touch_failed"})
                return
        }
        report["added"] = added
        report["price_updated"] = priceUpdated
        report["products_created"] = created
        report["unchanged"] = unchanged
        report["failed"] = failed
        if err := writePlatformAuditLog(ctx, tx, principal,
                "library.import", "create", "product_library", c.Param("id"), "",
                map[string]any{"report": report},
                fmt.Sprintf("استيراد مكتبة: %d صفًا — %d إضافة، %d تحديث سعر، %d منتج جديد", len(rows), added, priceUpdated, created)); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }
        report["errors"] = importErrors
        c.JSON(http.StatusOK, gin.H{"data": report})
}

// ListPlatformCatalogProducts — GET /platform-admin/catalog/products
// The central catalog browser backing the «إضافة منتج من الكتالوج» picker:
// barcode-exact and prefix matches rank first, then name matches; each row
// carries the libraries it currently belongs to.
func (h *Handler) ListPlatformCatalogProducts(c *gin.Context) {
        page := parsePositiveInt(c.Query("page"), 1)
        pageSize := parsePositiveInt(c.Query("page_size"), 20)
        if pageSize > 100 {
                pageSize = 100
        }
        search := strings.TrimSpace(c.Query("search"))
        ctx := c.Request.Context()

        where := ""
        args := []any{}
        if search != "" {
                where = ` WHERE name ILIKE '%' || $1 || '%' OR generic_name ILIKE '%' || $1 || '%' OR barcode = $2 OR barcode ILIKE $2 || '%'`
                args = append(args, escapeLike(search), escapeLike(search))
        }

        var total int64
        if err := h.db.QueryRow(ctx,
                `SELECT COUNT(*) FROM global_products`+where, args...,
        ).Scan(&total); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_count_failed"})
                return
        }

        qargs := append(args, pageSize, (page-1)*pageSize)
        order := ` ORDER BY name LIMIT $` + itoa(len(qargs)-1) + ` OFFSET $` + itoa(len(qargs))
        rows, err := h.db.Query(ctx, `
                SELECT id::text, name, generic_name, strength, dosage_form::text, product_category::text,
                       barcode, manufacturer_name, is_verified, source, is_active
                FROM global_products`+where+order, qargs...)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_query_failed"})
                return
        }
        defer rows.Close()

        type catalogRow struct {
                ID             string          `json:"id"`
                Name           string          `json:"name"`
                GenericName    *string         `json:"generic_name"`
                Strength       *string         `json:"strength"`
                DosageForm     string          `json:"dosage_form"`
                ProductCategory string         `json:"product_category"`
                Barcode        *string         `json:"barcode"`
                Manufacturer   *string         `json:"manufacturer_name"`
                IsVerified     bool            `json:"is_verified"`
                Source         string          `json:"source"`
                IsActive       bool            `json:"is_active"`
                Libraries      json.RawMessage `json:"libraries"`
        }
        items := []catalogRow{}
        ids := []string{}
        for rows.Next() {
                var r catalogRow
                if err := rows.Scan(&r.ID, &r.Name, &r.GenericName, &r.Strength, &r.DosageForm,
                        &r.ProductCategory, &r.Barcode, &r.Manufacturer, &r.IsVerified, &r.Source,
                        &r.IsActive); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_scan_failed"})
                        return
                }
                r.Libraries = json.RawMessage("[]")
                items = append(items, r)
                ids = append(ids, r.ID)
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_scan_failed"})
                return
        }

        // Library membership for the page rows (single query, keyed in Go).
        member := map[string][]gin.H{}
        if len(ids) > 0 {
                mrows, err := h.db.Query(ctx, `
                        SELECT lp.global_product_id::text, l.id::text, l.name
                        FROM library_products lp
                        JOIN product_libraries l ON l.id = lp.library_id
                        WHERE lp.global_product_id = ANY($1::uuid[])
                        ORDER BY l.name
                `, ids)
                if err == nil {
                        for mrows.Next() {
                                var gpID, libID, libName string
                                if err := mrows.Scan(&gpID, &libID, &libName); err == nil {
                                        member[gpID] = append(member[gpID], gin.H{"id": libID, "name": libName})
                                }
                        }
                        mrows.Close()
                }
        }
        for i := range items {
                if libs := member[items[i].ID]; len(libs) > 0 {
                        blob, _ := json.Marshal(libs)
                        items[i].Libraries = blob
                }
        }

        c.JSON(http.StatusOK, gin.H{
                "data": items,
                "pagination": gin.H{
                        "total": total, "page": page, "page_size": pageSize,
                        "total_pages": (total + int64(pageSize) - 1) / int64(pageSize),
                },
        })
}

// UpdatePlatformCatalogProduct — PUT /platform-admin/catalog/products/:id
// Full metadata edit of a central catalog product + the verification badge.
// Metadata fixes propagate as «metadata_changed» rows into EVERY library
// containing the product, tagged with each library's draft version — that
// is how a name/strength correction later reaches pharmacies through the
// same diff channel as prices.
func (h *Handler) UpdatePlatformCatalogProduct(c *gin.Context) {
        var payload struct {
                Name                 *string `json:"name"`
                GenericName          *string `json:"generic_name"`
                BrandName            *string `json:"brand_name"`
                DosageForm           *string `json:"dosage_form"`
                Strength             *string `json:"strength"`
                ProductCategory      *string `json:"product_category"`
                RequiresPrescription *string `json:"requires_prescription"`
                Barcode              *string `json:"barcode"`
                ManufacturerName     *string `json:"manufacturer_name"`
                ManufacturerCountry  *string `json:"manufacturer_country"`
                ActiveIngredient     *string `json:"active_ingredient"`
                AtcCode              *string `json:"atc_code"`
                TherapeuticClass     *string `json:"therapeutic_class"`
                StorageInstructions  *string `json:"storage_instructions"`
                Description          *string `json:"description"`
                IsVerified           *bool   `json:"is_verified"`
                IsActive             *bool   `json:"is_active"`
        }
        if err := c.ShouldBindJSON(&payload); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        if payload.DosageForm != nil && !validDosageForms[*payload.DosageForm] {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_dosage_form", "message": "الشكل الصيدلي غير معروف"})
                return
        }
        if payload.ProductCategory != nil && !validProductCategories[*payload.ProductCategory] {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_category", "message": "تصنيف المنتج غير معروف"})
                return
        }
        if payload.RequiresPrescription != nil {
                v := *payload.RequiresPrescription
                if v != "yes" && v != "no" && v != "otc_only" {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_prescription", "message": "قيمة وصفة الطبيب يجب أن تكون: yes أو no أو otc_only"})
                        return
                }
        }
        if payload.Barcode != nil {
                *payload.Barcode = strings.TrimSpace(*payload.Barcode)
        }
        if payload.Name != nil && strings.TrimSpace(*payload.Name) == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_name", "message": "اسم المنتج لا يمكن أن يكون فارغًا"})
                return
        }

        ctx := c.Request.Context()
        principal, _ := auth.PrincipalFromContext(c)
        tx, err := h.db.Begin(ctx)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_begin_failed"})
                return
        }
        defer func() { _ = tx.Rollback(ctx) }()

        var (
                oldName string
                oldCode *string
        )
        err = tx.QueryRow(ctx,
                `SELECT name, barcode FROM global_products WHERE id = $1::uuid FOR UPDATE`,
                c.Param("id")).Scan(&oldName, &oldCode)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "catalog_product_not_found", "message": "المنتج غير موجود في الكتالوج المركزي"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_query_failed"})
                return
        }

        tag, err := tx.Exec(ctx, `
                UPDATE global_products SET
                        name                 = COALESCE($2, name),
                        generic_name         = COALESCE($3, generic_name),
                        brand_name           = COALESCE($4, brand_name),
                        dosage_form          = COALESCE($5::dosage_form, dosage_form),
                        strength             = COALESCE($6, strength),
                        product_category     = COALESCE($7::product_category, product_category),
                        requires_prescription = COALESCE($8::prescription_required, requires_prescription),
                        barcode              = COALESCE(NULLIF($9, ''), barcode),
                        manufacturer_name    = COALESCE($10, manufacturer_name),
                        manufacturer_country = COALESCE($11, manufacturer_country),
                        active_ingredient    = COALESCE($12, active_ingredient),
                        atc_code             = COALESCE($13, atc_code),
                        therapeutic_class    = COALESCE($14, therapeutic_class),
                        storage_instructions = COALESCE($15, storage_instructions),
                        description          = COALESCE($16, description),
                        is_verified          = COALESCE($17, is_verified),
                        is_active            = COALESCE($18, is_active),
                        updated_at           = NOW()
                WHERE id = $1::uuid
        `, c.Param("id"),
                payload.Name, payload.GenericName, payload.BrandName,
                payload.DosageForm, payload.Strength, payload.ProductCategory,
                payload.RequiresPrescription, payload.Barcode,
                payload.ManufacturerName, payload.ManufacturerCountry,
                payload.ActiveIngredient, payload.AtcCode, payload.TherapeuticClass,
                payload.StorageInstructions, payload.Description,
                payload.IsVerified, payload.IsActive)
        if err != nil {
                if isUniqueViolation(err) {
                        c.JSON(http.StatusConflict, gin.H{"error": "barcode_taken", "message": "الباركود مسجل بالفعل لمنتج آخر في الكتالوج"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_update_failed"})
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "catalog_product_not_found", "message": "المنتج غير موجود في الكتالوج المركزي"})
                return
        }

        // Propagate the metadata fix into every library containing the product.
        // NULLIF handles «clear this field» via empty strings coming from the UI.
        summary := "تصحيح بيانات منتج من قبل المنصة"
        if payload.Name != nil && strings.TrimSpace(*payload.Name) != "" && *payload.Name != oldName {
                summary = "تصحيح بيانات منتج: " + oldName + " ← " + strings.TrimSpace(*payload.Name)
        }
        if _, err := tx.Exec(ctx, `
                INSERT INTO library_changes (library_id, global_product_id, version, change_type, summary)
                SELECT lp.library_id, $1::uuid,
                       CASE WHEN l.is_published THEN l.version + 1 ELSE l.version END,
                       'metadata_changed', $2
                FROM library_products lp
                JOIN product_libraries l ON l.id = lp.library_id
                WHERE lp.global_product_id = $1::uuid
        `, c.Param("id"), summary); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "library_change_log_failed"})
                return
        }

        if err := writePlatformAuditLog(ctx, tx, principal,
                "catalog.product_update", "update", "global_product", c.Param("id"), "",
                map[string]any{"old_name": oldName, "old_barcode": oldCode, "barcode_changed": payload.Barcode != nil},
                summary); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "audit_failed"})
                return
        }
        if err := tx.Commit(ctx); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "tx_commit_failed"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"updated": true}})
}
