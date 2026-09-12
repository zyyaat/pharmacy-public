package handlers

import (
        "encoding/json"
        "errors"
        "fmt"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/jackc/pgx/v5/pgconn"

        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/barcode"
        "github.com/pharmacy-os/backend/internal/money"
)

// importOptions — خيارات التنفيذ التي يرسلها المعالج بعد تأكيد المستخدم.
type importOptions struct {
        DuplicateStrategy string `json:"duplicate_strategy"` // skip | update
        QuantityUnit      string `json:"quantity_unit"`      // box | strip
        ImportStock       bool   `json:"import_stock"`
}

// importRow — صف منتج صالح جاهز للترحيل (بعد التحقق والتحويل).
type importRow struct {
        lineNo       int
        name         string
        barcode      string // فارغ = بدون باركود
        selling      money.Piastres
        cost         money.Piastres
        hasCost      bool
        partial      money.Piastres
        hasPartial   bool
        quantityBase int64 // بالوحدة الأساسية (شرائط للـ BOX_STRIP)
        unitsPerBox  int
        packaging    string // WHOLE_ONLY | BOX_STRIP
        minStock     int64
        hasMinStock  bool
        expiry       string // YYYY-MM-DD أو فارغ
        batchNumber  string
        genericName  string
        strength     string
        dosageForm   string
}

// normalizeImportName — تطبيع اسم للمطابقة: أحرف صغيرة ومسافات منهارة.
func normalizeImportName(s string) string {
        return strings.Join(strings.Fields(strings.ToLower(strings.TrimSpace(s))), " ")
}

// validateImportRow — يتحقق من صف خام ويعيد الصف المحوَّل أو سبب الرفض بالعربية.
func validateImportRow(row []string, mapping map[string]int, opts importOptions) (importRow, string) {
        var out importRow

        out.name = cell(row, mapping[ifName])
        if out.name == "" {
                return out, "اسم الصنف فارغ — العمود الأساسي المطلوب"
        }
        out.barcode = strings.Trim(cell(row, mapping[ifBarcode]), `"`)
        out.genericName = cell(row, mapping[ifGenericName])
        out.strength = cell(row, mapping[ifStrength])
        out.dosageForm = mapImportDosageForm(cell(row, mapping[ifDosageForm]))
        out.batchNumber = cell(row, mapping[ifBatch])

        // سعر البيع
        if idx := mapping[ifSellingPrice]; idx >= 0 {
                if raw := cell(row, idx); raw != "" {
                        v, ok := parseArabicNumber(raw)
                        if !ok {
                                return out, fmt.Sprintf("سعر البيع «%s» رقم غير مفهوم", raw)
                        }
                        p := egpToPiastres(v)
                        if p < 0 || !money.Piastres(p).Valid() {
                                return out, "سعر البيع قيمة غير صالحة"
                        }
                        out.selling = money.Piastres(p)
                }
        }
        // سعر الشراء
        if idx := mapping[ifCostPrice]; idx >= 0 {
                if raw := cell(row, idx); raw != "" {
                        v, ok := parseArabicNumber(raw)
                        if !ok {
                                return out, fmt.Sprintf("سعر الشراء «%s» رقم غير مفهوم", raw)
                        }
                        p := egpToPiastres(v)
                        if p < 0 || !money.Piastres(p).Valid() {
                                return out, "سعر الشراء قيمة غير صالحة"
                        }
                        out.cost = money.Piastres(p)
                        out.hasCost = true
                }
        }
        // الشرائط بالعلبة + استنتاج نوع التغليف (للمنتجات الجديدة)
        upb := 1
        if idx := mapping[ifUnitsPerBox]; idx >= 0 {
                if raw := cell(row, idx); raw != "" {
                        v, ok := parseArabicNumber(raw)
                        if !ok || v != float64(int64(v)) || int64(v) < 0 {
                                return out, fmt.Sprintf("عدد الشرائط «%s» ليس عددًا صحيحًا", raw)
                        }
                        upb = int(v)
                }
        }
        if upb >= 2 {
                out.packaging = packagingBoxStrip
                out.unitsPerBox = upb
        } else {
                out.packaging = packagingWholeOnly
                out.unitsPerBox = 1
        }
        // سعر الشريط: يُقبل للـ BOX_STRIP فقط، والافتراضي كلمة قسمة سعر العلبة
        if out.packaging == packagingBoxStrip {
                if idx := mapping[ifPartialPrice]; idx >= 0 {
                        if raw := cell(row, idx); raw != "" {
                                v, ok := parseArabicNumber(raw)
                                if !ok {
                                        return out, fmt.Sprintf("سعر الشريط «%s» رقم غير مفهوم", raw)
                                }
                                p := egpToPiastres(v)
                                if p < 0 || !money.Piastres(p).Valid() {
                                        return out, "سعر الشريط قيمة غير صالحة"
                                }
                                out.partial = money.Piastres(p)
                                out.hasPartial = true
                        }
                }
                if !out.hasPartial {
                        fallback := int64(out.selling) / int64(out.unitsPerBox)
                        if fallback <= 0 {
                                return out, "منتج بيع بالشريط: سعر الشريط مطلوب لعدم إمكانية اشتقاقه من سعر العلبة"
                        }
                        out.partial = money.Piastres(fallback)
                        out.hasPartial = true
                }
        }
        // الكمية
        if idx := mapping[ifQuantity]; idx >= 0 {
                if raw := cell(row, idx); raw != "" {
                        v, ok := parseArabicNumber(raw)
                        if !ok || v != float64(int64(v)) || v < 0 {
                                return out, fmt.Sprintf("الكمية «%s» ليست عددًا صحيحًا غير سالب", raw)
                        }
                        qty := int64(v)
                        if opts.ImportStock && qty > 0 {
                                if opts.QuantityUnit == "strip" && out.packaging == packagingBoxStrip {
                                        out.quantityBase = qty
                                } else {
                                        out.quantityBase = qty * int64(out.unitsPerBox)
                                }
                        }
                }
        }
        // حد الطلب (بالعلبة الكاملة — نفس دلالة النظام)
        if idx := mapping[ifMinStock]; idx >= 0 {
                if raw := cell(row, idx); raw != "" {
                        v, ok := parseArabicNumber(raw)
                        if !ok || v != float64(int64(v)) || v < 0 {
                                return out, fmt.Sprintf("حد الطلب «%s» ليس عددًا صحيحًا غير سالب", raw)
                        }
                        out.minStock = int64(v)
                        out.hasMinStock = true
                }
        }
        // الصلاحية
        if idx := mapping[ifExpiry]; idx >= 0 {
                if raw := cell(row, idx); raw != "" {
                        t, ok := parseImportDate(raw)
                        if !ok {
                                return out, fmt.Sprintf("تاريخ الصلاحية «%s» بصيغة غير مفهومة", raw)
                        }
                        out.expiry = t.Format("2006-01-02")
                }
        }
        return out, ""
}

// existingProduct — منتج قائم بالصيدلية يُستخدم في مطابقة التكرار.
type existingProduct struct {
        id              string
        barcode         string
        name            string
        selling         money.Piastres
        cost            money.Piastres
        partial         *int64
        unitsPerBox     int
        packaging       string
}

// ExecuteProductImport — الخطوة 2: POST /pharmacy/imports/products/execute
// يستقبل نفس الملف + الربط المؤكد + الخيارات؛ الصفوف الصالحة تُرحَّل ذريًا
// (معاملة واحدة) والصفوف المرفوضة تعود بأسبابها في تقرير مفصل.
func (h *Handler) ExecuteProductImport(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.PharmacyID == "" || principal.ID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_mutation_account_required", "message": "حساب مدير أو موظف صيدلية مطلوب"})
                return
        }
        fh, err := c.FormFile("file")
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "file_required", "message": "يرجى رفع ملف Excel (xlsx) أو CSV"})
                return
        }
        mappingRaw := c.PostForm("mapping")
        optionsRaw := c.PostForm("options")
        if strings.TrimSpace(mappingRaw) == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "mapping_required", "message": "ربط الأعمدة مطلوب"})
                return
        }
        var mapping map[string]int
        if err := json.Unmarshal([]byte(mappingRaw), &mapping); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_mapping", "message": "ربط الأعمدة غير صالح"})
                return
        }
        if mapping[ifName] < 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "name_column_required", "message": "يجب تحديد عمود اسم الصنف"})
                return
        }
        opts := importOptions{DuplicateStrategy: "skip", QuantityUnit: "box", ImportStock: true}
        if strings.TrimSpace(optionsRaw) != "" {
                if err := json.Unmarshal([]byte(optionsRaw), &opts); err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_options", "message": "خيارات الاستيراد غير صالحة"})
                        return
                }
        }
        if opts.DuplicateStrategy != "skip" && opts.DuplicateStrategy != "update" {
                opts.DuplicateStrategy = "skip"
        }
        if opts.QuantityUnit != "box" && opts.QuantityUnit != "strip" {
                opts.QuantityUnit = "box"
        }

        headers, rows, _, perr := parseImportFile(fh)
        if perr != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": perr.Error(), "message": "تعذر تحليل الملف — أعد المحاولة من خطوة المعاينة"})
                return
        }
        // ضبط حدود الربط على أعمدة الملف الفعلية
        for f, idx := range mapping {
                if idx >= len(headers) {
                        mapping[f] = -1
                }
        }

        report := gin.H{
                "total_rows": len(rows), "created": 0, "updated": 0, "skipped": 0,
                "failed": 0, "stock_lines": 0, "errors": []gin.H{},
        }
        errorsOut := []gin.H{}
        addError := func(line int, name, reason string) {
                if len(errorsOut) < importErrorCap {
                        errorsOut = append(errorsOut, gin.H{"row": line, "name": name, "reason": reason})
                }
        }

        // التحقق الكامل قبل فتح المعاملة — المرفوض لا يدخل الترحيل أصلًا
        type classified struct {
                row    importRow
                action string // create | update | skip | fail
                reason string
        }
        plans := make([]classified, 0, len(rows))
        for i, r := range rows {
                line := i + 1
                allEmpty := true
                for _, cc := range r {
                        if cc != "" {
                                allEmpty = false
                                break
                        }
                }
                if allEmpty {
                        continue // الصفوف الفارغة تُهمل بصمت
                }
                ir, verr := validateImportRow(r, mapping, opts)
                ir.lineNo = line
                if verr != "" {
                        plans = append(plans, classified{row: ir, action: "fail", reason: verr})
                        continue
                }
                plans = append(plans, classified{row: ir, action: "pending"})
        }

        tx, err := h.db.Begin(c.Request.Context())
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر بدء الترحيل"})
                return
        }
        defer func() { _ = tx.Rollback(c.Request.Context()) }()

        if _, err := tx.Exec(c.Request.Context(), `
                SELECT set_config('app.current_pharmacy_id', $1, true),
                       set_config('app.current_user_id', $2, true)
        `, principal.PharmacyID, principal.ID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر إعداد نطاق الصيدلية"})
                return
        }

        // جرد منتجات الصيدلية الحالية للمطابقة (باركود ثم اسم مطبَّع)
        existing := map[string]existingProduct{} // مفتاحه الباركود الصغير
        existingByName := map[string]existingProduct{}
        rows0, err := tx.Query(c.Request.Context(), `
                SELECT pp.id::text, COALESCE(gp.barcode, ''), gp.name,
                       pp.selling_price::bigint, COALESCE(pp.cost_price, 0)::bigint,
                       pp.partial_selling_price::bigint, pp.units_per_box, pp.packaging_type
                FROM pharmacy_products pp
                JOIN global_products gp ON gp.id = pp.global_product_id
                WHERE pp.pharmacy_id = $1 AND COALESCE(pp.is_discontinued, false) = false
        `, principal.PharmacyID)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر جرد المنتجات الحالية"})
                return
        }
        for rows0.Next() {
                var ep existingProduct
                var partial *int64
                if err := rows0.Scan(&ep.id, &ep.barcode, &ep.name, &ep.selling, &ep.cost, &partial, &ep.unitsPerBox, &ep.packaging); err == nil {
                        ep.partial = partial
                        if ep.barcode != "" {
                                existing[strings.ToLower(ep.barcode)] = ep
                        }
                        existingByName[normalizeImportName(ep.name)] = ep
                }
        }
        rows0.Close()

        // فرع مخزون الصيدلية (يُحدد مرة واحدة عند أول صف يحتاج رصيدًا)
        var branchID string
        branchReady := false
        resolveBranch := func() (string, bool) {
                if branchReady {
                        return branchID, branchID != ""
                }
                branchReady = true
                bid, berr := branchForPrincipal(c, tx, principal)
                if berr != nil {
                        return "", false
                }
                branchID = bid
                return branchID, true
        }
        employeeID, companyUserID := actorIDs(principal)
        importStamp := "IMPORT-" + time.Now().UTC().Format("20060102150405")

        // تعقب ما أُنشئ داخل نفس الملف (مكررات الملف نفسه)
        createdByBarcode := map[string]string{}
        createdByName := map[string]string{}

        created, updated, skipped, failed, stockLines := 0, 0, 0, 0, 0

        for _, plan := range plans {
                ir := plan.row
                switch plan.action {
                case "fail":
                        failed++
                        addError(ir.lineNo, ir.name, plan.reason)
                        continue
                case "pending":
                        // تحديد المطابقة: باركود أولًا ثم الاسم المطبَّع
                        // مكرر داخل الملف نفسه: أول ورود فقط يُرحَّل — البقية تُهمل دائمًا
                        if ir.barcode != "" {
                            if _, ok := createdByBarcode[strings.ToLower(ir.barcode)]; ok {
                                skipped++
                                continue
                            }
                        }
                        if _, ok := createdByName[normalizeImportName(ir.name)]; ok {
                            skipped++
                            continue
                        }
                        // تحديد المطابقة مع المنتجات القائمة: باركود أولًا ثم الاسم المطبَّع
                        var matched *existingProduct
                        if ir.barcode != "" {
                            if ep, ok := existing[strings.ToLower(ir.barcode)]; ok {
                                matched = &ep
                            }
                        }
                        if matched == nil {
                            if ep, ok := existingByName[normalizeImportName(ir.name)]; ok {
                                matched = &ep
                            }
                        }
                        
                        if matched != nil {
                                if opts.DuplicateStrategy == "skip" {
                                        skipped++
                                        continue
                                }
                                // تحديث: الأسعار وحد الطلب فقط — المخزون القائم والتغليف لا يُلمسان
                                newSelling := matched.selling
                                if int64(ir.selling) > 0 {
                                    newSelling = ir.selling
                                }
                                var costArg *int64
                                if ir.hasCost {
                                    v := int64(ir.cost)
                                    costArg = &v
                                }
                                var partialArg *int64
                                if matched.partial != nil {
                                    v := *matched.partial
                                    partialArg = &v
                                }
                                if ir.hasPartial {
                                    v := int64(ir.partial)
                                    partialArg = &v
                                }
                                if matched.packaging == packagingBoxStrip && (partialArg == nil || *partialArg <= 0) {
                                    failed++
                                    addError(ir.lineNo, ir.name, "منتج بيع بالشريط بدون سعر شريط صالح — أدخل سعر الشريط")
                                    continue
                                }
                                upbArg := -1 // -1 = لا تغيير
                                if matched.packaging == packagingBoxStrip && ir.unitsPerBox >= 2 {
                                    upbArg = ir.unitsPerBox
                                }
                                minArg := -1 // -1 = لا تغيير
                                if ir.hasMinStock {
                                    minArg = int(ir.minStock)
                                }
                                if _, err := tx.Exec(c.Request.Context(), `
                                    UPDATE pharmacy_products SET
                                        selling_price = $2,
                                        cost_price = COALESCE($3, cost_price),
                                        partial_selling_price = COALESCE($4, partial_selling_price),
                                        units_per_box = CASE WHEN $5::int >= 2 AND packaging_type = 'BOX_STRIP' THEN $5::int ELSE units_per_box END,
                                        min_stock_level = CASE WHEN $6::int >= 0 THEN $6::int ELSE min_stock_level END,
                                        updated_at = NOW()
                                    WHERE id = $1
                                `, matched.id, newSelling, costArg, partialArg, upbArg, minArg); err != nil {
                                    c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر تحديث منتج قائم: " + ir.name})
                                    return
                                }
                                updated++
                                continue
                        }

                        // إنشاء منتج جديد — تحقق الباركود العالمي (فهرس فريد عالمي)
                        if ir.barcode != "" {
                                var otherID string
                                err := tx.QueryRow(c.Request.Context(), `
                                        SELECT id::text FROM global_products WHERE barcode = $1
                                `, ir.barcode).Scan(&otherID)
                                if err == nil {
                                        failed++
                                        addError(ir.lineNo, ir.name, "الباركود مسجل في النظام لصيدلية أخرى — راجع الصنف")
                                        continue
                                }
                                if !errors.Is(err, pgx.ErrNoRows) {
                                        c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر التحقق من الباركود"})
                                        return
                                }
                        }

                        defaultUnit := "box"
                        if ir.packaging == packagingBoxStrip {
                                defaultUnit = "strip"
                        }
                        var globalProductID string
                        // barcode_type is derived mechanically even on the import
                        // path, so the locked vocabulary stays consistent no matter
                        // which door a code entered through (review §2.2).
                        importBarcodeType := any(nil)
                        if ir.barcode != "" {
                                importBarcodeType = barcode.DeriveType(ir.barcode)
                        }
                        err := tx.QueryRow(c.Request.Context(), `
                                INSERT INTO global_products (
                                        name, generic_name, dosage_form, strength, barcode, barcode_type, default_unit,
                                        product_category, requires_prescription, is_active, created_by
                                ) VALUES ($1, NULLIF($2, ''), $3::dosage_form, NULLIF($4, ''), NULLIF($5, ''), $8, $6::unit_type,
                                          'medication'::product_category, 'no'::prescription_required, true, NULLIF($7, '')::uuid)
                                RETURNING id::text
                        `, ir.name, ir.genericName, ir.dosageForm, ir.strength, ir.barcode, defaultUnit, employeeID, importBarcodeType).Scan(&globalProductID)
                        if err != nil {
                                var pgErr *pgconn.PgError
                                if errors.As(err, &pgErr) && pgErr.Code == "23505" {
                                        failed++
                                        addError(ir.lineNo, ir.name, "الباركود مستخدم بالفعل في النظام")
                                        continue
                                }
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر إنشاء الصنف: " + ir.name})
                                return
                        }
                        var pharmacyProductID string
                        var partialArg *int64
                        if ir.packaging == packagingBoxStrip {
                                v := int64(ir.partial)
                                partialArg = &v
                        }
                        if err := tx.QueryRow(c.Request.Context(), `
                                INSERT INTO pharmacy_products (
                                        pharmacy_id, global_product_id, cost_price, selling_price,
                                        partial_selling_price, min_stock_level, packaging_type, units_per_box,
                                        is_active, is_discontinued
                                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, false)
                                RETURNING id::text
                        `, principal.PharmacyID, globalProductID, nullInt64(ir.cost), ir.selling,
                                partialArg, ir.minStock, ir.packaging, ir.unitsPerBox).Scan(&pharmacyProductID); err != nil {
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر ربط الصنف بالصيدلية: " + ir.name})
                                return
                        }
                        if ir.barcode != "" {
                                createdByBarcode[strings.ToLower(ir.barcode)] = pharmacyProductID
                        }
                        createdByName[normalizeImportName(ir.name)] = pharmacyProductID

                        // الرصيد الافتتاحي إن وُجد
                        if ir.quantityBase > 0 {
                                branch, okBranch := resolveBranch()
                                if !okBranch {
                                        c.JSON(http.StatusBadRequest, gin.H{"error": "branch_required", "message": "يجب تحديد فرع قبل إضافة المخزون — أضف رصيدًا يدويًا بعد الترحيل"})
                                        // الصنف أُنشئ لكن بلا رصيد؛ نكمل الباقي بلا خطأ دفعة واحدة
                                        created++
                                        continue
                                }
                                unitCost := ir.cost
                                if !ir.hasCost {
                                        unitCost = 0
                                }
                                perUnit := unitCost
                                if ir.packaging == packagingBoxStrip {
                                        perUnit = unitCost.DivRoundHalfUp(int64(ir.unitsPerBox))
                                }
                                batchNumber := ir.batchNumber
                                if batchNumber == "" {
                                        batchNumber = importStamp
                                }
                                var batchID string
                                if err := tx.QueryRow(c.Request.Context(), `
                                        INSERT INTO inventory_batches (
                                                pharmacy_product_id, branch_id, batch_number, quantity, unit,
                                                cost_per_unit, expiry_date, received_by, reference_type
                                        ) VALUES ($1, $2, $3, $4, $5::unit_type, $6, NULLIF($7, '')::date, NULLIF($8, '')::uuid, $9)
                                        RETURNING id::text
                                `, pharmacyProductID, branch, batchNumber, ir.quantityBase,
                                        map[bool]string{true: "strip", false: "box"}[ir.packaging == packagingBoxStrip],
                                        perUnit, ir.expiry, employeeID, importBatchRef).Scan(&batchID); err != nil {
                                        c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر إنشاء رصيد المخزون: " + ir.name})
                                        return
                                }
                                if _, err := tx.Exec(c.Request.Context(), `
                                        INSERT INTO stock_movements (
                                                batch_id, movement_type, quantity, unit, quantity_before,
                                                quantity_after, unit_cost, total_cost, created_by, created_by_company_user_id, reason
                                        ) VALUES ($1, 'purchase'::movement_type, $2, $3::unit_type, 0, $2, $4, $5, NULLIF($6, '')::uuid, NULLIF($7, '')::uuid, $8)
                                `, batchID, ir.quantityBase,
                                        map[bool]string{true: "strip", false: "box"}[ir.packaging == packagingBoxStrip],
                                        perUnit, perUnit.MulQty(ir.quantityBase), employeeID, companyUserID, importBatchNote); err != nil {
                                        c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر تسجيل حركة المخزون: " + ir.name})
                                        return
                                }
                                stockLines++
                        }
                        created++
                }
        }

        if err := tx.Commit(c.Request.Context()); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "import_failed", "message": "تعذر تأكيد الترحيل"})
                return
        }

        report["created"] = created
        report["updated"] = updated
        report["skipped"] = skipped
        report["failed"] = failed
        report["stock_lines"] = stockLines
        report["errors"] = errorsOut
        c.JSON(http.StatusOK, gin.H{"data": report})
}

// nullInt64 — يحول صفر إلى NULL لحقول التكلفة الاختيارية.
func nullInt64(v money.Piastres) interface{} {
        if v == 0 {
                return nil
        }
        return int64(v)
}

// ProductImportTemplate — GET /pharmacy/imports/products/template
// نموذج CSV بترميز UTF-8 مع BOM (يفتح في Excel مباشرة بلا تشويه عربي).
func (h *Handler) ProductImportTemplate(c *gin.Context) {
        var b strings.Builder
        b.WriteByte(0xEF)
        b.WriteByte(0xBB)
        b.WriteByte(0xBF)
        headers := []string{
                "اسم الصنف", "الباركود", "السعر", "سعر الشراء", "سعر الشريط",
                "عدد الشرائط بالعلبة", "الكمية", "حد الطلب", "الصلاحية", "رقم التشغيلة", "الاسم العلمي", "التركيز",
        }
        writeCSVLine(&b, headers)
        writeCSVLine(&b, []string{"بانادول اكسترا", "9800501", "25", "18", "3", "12", "10", "5", "2027-06-01", "A-12", "Paracetamol", "500mg"})
        writeCSVLine(&b, []string{"مرهم بيتاميثازون", "9800502", "18.5", "12", "", "1", "20", "3", "01/09/2027", "", "Betamethasone", "0.1%"})
        c.Header("Content-Disposition", `attachment; filename="product-import-template.csv"`)
        c.Data(http.StatusOK, "text/csv; charset=utf-8", []byte(b.String()))
}

// writeCSVLine — سطر CSV واحد مع اقتباس ذكي للحقول.
func writeCSVLine(b *strings.Builder, fields []string) {
        quoted := make([]string, len(fields))
        for i, f := range fields {
                if strings.ContainsAny(f, ",\"\n\r") {
                        quoted[i] = `"` + strings.ReplaceAll(f, `"`, `""`) + `"`
                } else {
                        quoted[i] = f
                }
        }
        b.WriteString(strings.Join(quoted, ","))
        b.WriteString("\r\n")
}
