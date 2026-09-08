package handlers

import (
        "context"
        "errors"
        "log"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"
        "github.com/jackc/pgx/v5/pgconn"

        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/money"
)

const (
        packagingWholeOnly = "WHOLE_ONLY"
        packagingBoxStrip  = "BOX_STRIP"

        minSaleQuantity = 1
        maxSaleQuantity = 1_000_000
)

// All money in this file is money.Piastres: an integer count of piastres
// (1 EGP = 100 piastres). No floating point value ever touches an amount.

type createPharmacyProductRequest struct {
        Name                        string `json:"name"`
        GenericName                 string `json:"generic_name"`
        DosageForm                  string `json:"dosage_form"`
        Strength                    string `json:"strength"`
        Barcode                     string `json:"barcode"`
        PackagingType               string `json:"packaging_type"`
        UnitsPerBox                 int64  `json:"units_per_box"`
        CostPricePiastres           int64  `json:"cost_price_piastres"`
        SellingPricePiastres        int64  `json:"selling_price_piastres"`
        PartialSellingPricePiastres *int64 `json:"partial_selling_price_piastres"`
        MinStockLevel               int64  `json:"min_stock_level"`
        InitialBoxes                int64  `json:"initial_boxes"`
        InitialStrips               int64  `json:"initial_strips"`
        BatchNumber                 string `json:"batch_number"`
        ExpiryDate                  string `json:"expiry_date"`
}

type posSaleRequest struct {
        Items          []posSaleItemRequest `json:"items"`
        IdempotencyKey string               `json:"idempotency_key"`
}

type posSaleItemRequest struct {
        PharmacyProductID string `json:"pharmacy_product_id"`
        SaleUnit          string `json:"sale_unit"`
        Quantity          int64  `json:"quantity"`
        // Client intent captured while the cashier was scanning. Both fields
        // are optional; when present the backend verifies them against the
        // authoritative prices and rejects the sale with 409 price_changed
        // instead of silently charging a stale price.
        ExpectedUnitPricePiastres *int64 `json:"expected_unit_price_piastres"`
        ExpectedLineTotalPiastres *int64 `json:"expected_line_total_piastres"`
}

type posPricingSnapshot struct {
        PackagingType string
        UnitsPerBox   int64
        BoxPrice      money.Piastres
        StripPrice    money.Piastres
}

// effectiveUnitPrice returns the authoritative price for one sale unit.
func (s posPricingSnapshot) effectiveUnitPrice(saleUnit string) money.Piastres {
        if saleUnit == "box" {
                return s.BoxPrice
        }
        return s.StripPrice
}

var errPOSSaleInsufficientStock = errors.New("insufficient stock for POS sale")
var errInvalidPOSSaleUnit = errors.New("invalid POS sale unit")

func (h *Handler) ListPharmacyProducts(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }

        search := strings.TrimSpace(c.Query("search"))
        rows, err := h.db.Query(c.Request.Context(), `
                SELECT pp.id::text, COALESCE(gp.name::text, ''), COALESCE(gp.generic_name::text, ''), COALESCE(gp.barcode::text, ''),
                       COALESCE(pp.packaging_type::text, ''), COALESCE(pp.units_per_box::int8, 1),
                       pp.selling_price::int8, COALESCE(pp.partial_selling_price::int8, 0),
                       ROUND(COALESCE(SUM(ci.quantity), 0))::int8
                FROM pharmacy_products pp
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN current_inventory ci ON ci.pharmacy_product_id = pp.id
                WHERE pp.pharmacy_id = $1
                  AND pp.is_active = true
                  AND ($2 = '' OR gp.name ILIKE '%' || $2 || '%' OR gp.barcode ILIKE '%' || $2 || '%')
                GROUP BY pp.id, gp.name, gp.generic_name, gp.barcode, pp.packaging_type,
                         pp.units_per_box, pp.selling_price, pp.partial_selling_price
                ORDER BY gp.name
                LIMIT 500
        `, pharmacyID, search)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "products_query_failed", "message": "تعذر تحميل المنتجات"})
                return
        }
        defer rows.Close()

        products := make([]gin.H, 0)
        for rows.Next() {
                var (
                        id, name, genericName, barcode, packagingType string
                        unitsPerBox                                   int64
                        sellingPrice, partialPrice, stock             money.Piastres
                )
                // stock reuses the Piastres scan type only because both are
                // int64 columns here; it is a count, not an amount.
                if err := rows.Scan(&id, &name, &genericName, &barcode, &packagingType, &unitsPerBox, &sellingPrice, &partialPrice, &stock); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "products_query_failed", "message": "تعذر قراءة المنتجات"})
                        return
                }
                products = append(products, gin.H{
                        "id": id, "name": name, "generic_name": genericName, "barcode": barcode,
                        "packaging_type": packagingType, "units_per_box": unitsPerBox,
                        "selling_price_piastres": sellingPrice, "partial_selling_price_piastres": partialPrice,
                        "stock": stock,
                })
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "products_query_failed", "message": "تعذر قراءة المنتجات"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": products})
}

func (h *Handler) CreatePharmacyProduct(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.PharmacyID == "" || principal.ID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_mutation_account_required", "message": "حساب مدير أو موظف صيدلية مطلوب"})
                return
        }

        var request createPharmacyProductRequest
        if err := c.ShouldBindJSON(&request); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_product", "message": "بيانات المنتج غير صحيحة"})
                return
        }
        request.Name = strings.TrimSpace(request.Name)
        request.GenericName = strings.TrimSpace(request.GenericName)
        request.DosageForm = strings.TrimSpace(request.DosageForm)
        request.Strength = strings.TrimSpace(request.Strength)
        request.Barcode = strings.TrimSpace(request.Barcode)
        request.PackagingType = strings.TrimSpace(request.PackagingType)
        request.BatchNumber = strings.TrimSpace(request.BatchNumber)
        if request.DosageForm == "" {
                request.DosageForm = "tablet"
        }
        if request.PackagingType == "" {
                request.PackagingType = packagingWholeOnly
        }

        boxCost := money.Piastres(request.CostPricePiastres)
        boxPrice := money.Piastres(request.SellingPricePiastres)
        validMoney := boxCost.Valid() && boxPrice.Valid() && request.MinStockLevel >= 0 &&
                request.InitialBoxes >= 0 && request.InitialStrips >= 0
        if request.Name == "" || request.Barcode == "" ||
                (request.PackagingType != packagingWholeOnly && request.PackagingType != packagingBoxStrip) ||
                !validMoney {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_product", "message": "يرجى إدخال اسم المنتج والباركود والأسعار والقيم غير السالبة"})
                return
        }
        if request.PackagingType == packagingWholeOnly {
                request.UnitsPerBox = 1
                request.PartialSellingPricePiastres = nil
                if request.InitialStrips != 0 {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_initial_stock", "message": "المنتج الذي يباع كعبوة كاملة لا يقبل كمية شرائط"})
                        return
                }
        } else {
                if request.UnitsPerBox < 2 {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_units_per_box", "message": "عدد الشرائط داخل العلبة يجب أن يكون 2 على الأقل"})
                        return
                }
                // The strip price is explicit and mandatory: deriving it by
                // dividing the box price would create fractional piastres,
                // which this system does not allow.
                if request.PartialSellingPricePiastres == nil || !money.Piastres(*request.PartialSellingPricePiastres).Valid() {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "partial_price_required", "message": "سعر بيع الشريط مطلوب ويجب أن يكون مبلغًا صحيحًا بالقروش"})
                        return
                }
        }

        baseQuantity := request.InitialBoxes*request.UnitsPerBox + request.InitialStrips
        baseUnit := "box"
        if request.PackagingType == packagingBoxStrip {
                baseUnit = "strip"
        }
        if baseQuantity > 0 && request.BatchNumber == "" {
                request.BatchNumber = "OPENING-" + time.Now().UTC().Format("20060102150405")
        }
        // Cost per base unit: the only cost division in the system. It uses
        // the documented half-up rounding so a box cost that does not divide
        // evenly contributes at most half a piastre of cost rounding.
        unitCost := boxCost
        if request.PackagingType == packagingBoxStrip {
                unitCost = boxCost.DivRoundHalfUp(request.UnitsPerBox)
        }
        employeeID, companyUserID := actorIDs(principal)

        tx, err := h.db.Begin(c.Request.Context())
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "product_create_failed", "message": "تعذر بدء حفظ المنتج"})
                return
        }
        defer func() { _ = tx.Rollback(c.Request.Context()) }()

        if _, err := tx.Exec(c.Request.Context(), `
                SELECT set_config('app.current_pharmacy_id', $1, true),
                       set_config('app.current_user_id', $2, true)
        `, principal.PharmacyID, principal.ID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "product_create_failed", "message": "تعذر إعداد نطاق الصيدلية"})
                return
        }

        defaultUnit := baseUnit
        var globalProductID string
        err = tx.QueryRow(c.Request.Context(), `
                INSERT INTO global_products (
                        name, generic_name, dosage_form, strength, barcode, default_unit,
                        product_category, requires_prescription, is_active, created_by
                ) VALUES ($1, NULLIF($2, ''), $3::dosage_form, NULLIF($4, ''), $5, $6::unit_type,
                          'medication'::product_category, 'no'::prescription_required, true, NULLIF($7, '')::uuid)
                RETURNING id::text
        `, request.Name, request.GenericName, request.DosageForm, request.Strength, request.Barcode, defaultUnit, employeeID).Scan(&globalProductID)
        if err != nil {
                var pgErr *pgconn.PgError
                if errors.As(err, &pgErr) && pgErr.Code == "23505" {
                        c.JSON(http.StatusConflict, gin.H{"error": "barcode_already_exists", "message": "هذا الباركود مستخدم من قبل"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "product_create_failed", "message": "تعذر حفظ بيانات المنتج"})
                return
        }

        var pharmacyProductID string
        err = tx.QueryRow(c.Request.Context(), `
                INSERT INTO pharmacy_products (
                        pharmacy_id, global_product_id, cost_price, selling_price,
                        partial_selling_price, min_stock_level, packaging_type, units_per_box,
                        is_active, is_discontinued
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, false)
                RETURNING id::text
        `, principal.PharmacyID, globalProductID, boxCost, boxPrice,
                request.PartialSellingPricePiastres, request.MinStockLevel, request.PackagingType, request.UnitsPerBox).Scan(&pharmacyProductID)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "product_create_failed", "message": "تعذر ربط المنتج بالصيدلية"})
                return
        }

        if baseQuantity > 0 {
                branchID, branchErr := branchForPrincipal(c, tx, principal)
                if branchErr != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "branch_required", "message": "يجب تحديد فرع قبل إضافة المخزون"})
                        return
                }
                var batchID string
                err = tx.QueryRow(c.Request.Context(), `
                        INSERT INTO inventory_batches (
                                pharmacy_product_id, branch_id, batch_number, quantity, unit,
                                cost_per_unit, expiry_date, received_by, reference_type
                        ) VALUES ($1, $2, $3, $4, $5::unit_type, $6, NULLIF($7, '')::date, NULLIF($8, '')::uuid, 'opening_balance')
                        RETURNING id::text
                `, pharmacyProductID, branchID, request.BatchNumber, baseQuantity, baseUnit, unitCost, request.ExpiryDate, employeeID).Scan(&batchID)
                if err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "product_create_failed", "message": "تعذر إنشاء رصيد المخزون"})
                        return
                }
                if _, err = tx.Exec(c.Request.Context(), `
                        INSERT INTO stock_movements (
                                batch_id, movement_type, quantity, unit, quantity_before,
                                quantity_after, unit_cost, total_cost, created_by, created_by_company_user_id, reason
                        ) VALUES ($1, 'purchase'::movement_type, $2, $3::unit_type, 0, $2, $4, $5, NULLIF($6, '')::uuid, NULLIF($7, '')::uuid, 'opening_balance')
                `, batchID, baseQuantity, baseUnit, unitCost, unitCost.MulQty(baseQuantity), employeeID, companyUserID); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "product_create_failed", "message": "تعذر تسجيل حركة المخزون"})
                        return
                }
        }

        if err := tx.Commit(c.Request.Context()); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "product_create_failed", "message": "تعذر تأكيد حفظ المنتج"})
                return
        }
        c.JSON(http.StatusCreated, gin.H{
                "data": gin.H{
                        "id": pharmacyProductID, "global_product_id": globalProductID,
                        "packaging_type": request.PackagingType, "units_per_box": request.UnitsPerBox,
                        "initial_base_quantity": baseQuantity,
                },
        })
}

func (h *Handler) LookupPOSProduct(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        barcode := strings.TrimSpace(c.Query("barcode"))
        if barcode == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "barcode_required", "message": "الباركود مطلوب"})
                return
        }

        var (
                id, name, genericName, productBarcode, packagingType string
                unitsPerBox                                          int64
                sellingPrice, partialPrice, stock                    money.Piastres
        )
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT pp.id::text, COALESCE(gp.name::text, ''), COALESCE(gp.generic_name::text, ''), COALESCE(gp.barcode::text, ''),
                       COALESCE(pp.packaging_type::text, ''), COALESCE(pp.units_per_box::int8, 1),
                       pp.selling_price::int8, COALESCE(pp.partial_selling_price::int8, 0),
                       ROUND(COALESCE(SUM(ci.quantity), 0))::int8
                FROM pharmacy_products pp
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN current_inventory ci ON ci.pharmacy_product_id = pp.id
                WHERE pp.pharmacy_id = $1 AND gp.barcode = $2
                  AND pp.is_active = true AND gp.is_active = true
                GROUP BY pp.id, gp.name, gp.generic_name, gp.barcode, pp.packaging_type,
                         pp.units_per_box, pp.selling_price, pp.partial_selling_price
        `, pharmacyID, barcode).Scan(&id, &name, &genericName, &productBarcode, &packagingType, &unitsPerBox, &sellingPrice, &partialPrice, &stock)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "product_not_found", "message": "لم يتم العثور على منتج بهذا الباركود"})
                return
        }
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "pos_lookup_failed", "message": "تعذر البحث عن المنتج"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "id": id, "name": name, "generic_name": genericName, "barcode": productBarcode,
                "packaging_type": packagingType, "units_per_box": unitsPerBox,
                "selling_price_piastres": sellingPrice, "partial_selling_price_piastres": partialPrice,
                "stock": stock,
        }})
}

// loadPOSPricing reads the authoritative pricing for one sale item inside
// the current transaction. A legacy BOX_STRIP product without an explicit
// strip price falls back to the documented half-up division of the box
// price; the product form now requires the explicit price, so the fallback
// only covers pre-existing rows.
func loadPOSPricing(ctx context.Context, tx pgx.Tx, pharmacyID, pharmacyProductID string) (posPricingSnapshot, error) {
        var snapshot posPricingSnapshot
        var boxPrice, partialPrice money.Piastres
        err := tx.QueryRow(ctx, `
                SELECT COALESCE(pp.packaging_type::text, ''), COALESCE(pp.units_per_box::int8, 1),
                       pp.selling_price::int8, pp.partial_selling_price::int8
                FROM pharmacy_products pp
                WHERE pp.id = $1 AND pp.pharmacy_id = $2 AND pp.is_active = true
        `, pharmacyProductID, pharmacyID).Scan(&snapshot.PackagingType, &snapshot.UnitsPerBox, &boxPrice, &partialPrice)
        if errors.Is(err, pgx.ErrNoRows) {
                return snapshot, errInvalidPOSSaleUnit
        }
        if err != nil {
                return snapshot, err
        }
        snapshot.BoxPrice = boxPrice
        snapshot.StripPrice = partialPrice
        if snapshot.PackagingType == packagingBoxStrip && !partialPrice.Valid() {
                snapshot.StripPrice = boxPrice.DivRoundHalfUp(snapshot.UnitsPerBox)
        }
        return snapshot, nil
}

func (h *Handler) CreatePOSSale(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.PharmacyID == "" || principal.ID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_mutation_account_required", "message": "حساب مدير أو موظف صيدلية مطلوب"})
                return
        }
        var request posSaleRequest
        if err := c.ShouldBindJSON(&request); err != nil || len(request.Items) == 0 || len(request.Items) > 100 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_sale", "message": "يجب إضافة منتج واحد على الأقل"})
                return
        }
        request.IdempotencyKey = strings.TrimSpace(request.IdempotencyKey)
        if request.IdempotencyKey != "" &&
                (len(request.IdempotencyKey) < 8 || len(request.IdempotencyKey) > 128) {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_idempotency_key", "message": "مفتاح إعادة المحاولة غير صالح"})
                return
        }
        for _, item := range request.Items {
                if item.PharmacyProductID == "" || item.Quantity < minSaleQuantity || item.Quantity > maxSaleQuantity ||
                        (item.SaleUnit != "box" && item.SaleUnit != "strip") {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_sale_item", "message": "بيانات أحد أصناف الفاتورة غير صحيحة"})
                        return
                }
        }
        branchID, err := h.findBranch(c, principal)
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "branch_required", "message": "يجب تحديد فرع قبل إتمام البيع"})
                return
        }
        employeeID, companyUserID := actorIDs(principal)

        tx, err := h.db.Begin(c.Request.Context())
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر بدء عملية البيع"})
                return
        }
        defer func() { _ = tx.Rollback(c.Request.Context()) }()
        if _, err := tx.Exec(c.Request.Context(), `
                SELECT set_config('app.current_pharmacy_id', $1, true),
                       set_config('app.current_user_id', $2, true)
        `, principal.PharmacyID, principal.ID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر إعداد نطاق الصيدلية"})
                return
        }

        // Idempotent replay: the same checkout retry returns the original
        // invoice instead of creating a second sale.
        if request.IdempotencyKey != "" {
                var existingID string
                var existingTotal money.Piastres
                err := tx.QueryRow(c.Request.Context(), `
                        SELECT id::text, total_amount::int8 FROM sales
                        WHERE pharmacy_id = $1 AND idempotency_key = $2
                `, principal.PharmacyID, request.IdempotencyKey).Scan(&existingID, &existingTotal)
                if err == nil {
                        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                                "sale_id": existingID, "total_amount_piastres": existingTotal, "replayed": true,
                        }})
                        return
                }
                if !errors.Is(err, pgx.ErrNoRows) {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر التحقق من الفاتورة"})
                        return
                }
        }

        // Phase 1: verify the client's price intent against the authoritative
        // prices BEFORE any mutation. Mismatched items are reported together
        // so the cashier's cart can be refreshed in one round trip.
        type priceMismatch struct {
                index                 int
                pharmacyProductID     string
                saleUnit              string
                quantity              int64
                unitPricePiastres     money.Piastres
                lineTotalPiastres     money.Piastres
        }
        snapshots := make([]posPricingSnapshot, len(request.Items))
        lineTotals := make([]money.Piastres, len(request.Items))
        mismatches := make([]gin.H, 0)
        for i, item := range request.Items {
                snapshot, pricingErr := loadPOSPricing(c.Request.Context(), tx, principal.PharmacyID, item.PharmacyProductID)
                if pricingErr != nil {
                        if errors.Is(pricingErr, errInvalidPOSSaleUnit) {
                                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_sale_unit", "message": "وحدة البيع غير مسموحة لأحد الأصناف"})
                                return
                        }
                        log.Printf("[POS] pricing read failed (product=%s): %v", item.PharmacyProductID, pricingErr)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر قراءة أسعار الفاتورة"})
                        return
                }
                if !snapshot.BoxPrice.Valid() || !snapshot.StripPrice.Valid() {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_product_pricing", "message": "أسعار أحد الأصناف غير مضبوطة، يرجى تحديث المنتج"})
                        return
                }
                // Sale-unit rules.
                if snapshot.PackagingType == packagingWholeOnly && item.SaleUnit != "box" {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_sale_unit", "message": "وحدة البيع غير مسموحة لأحد الأصناف"})
                        return
                }
                if snapshot.PackagingType == packagingBoxStrip && item.SaleUnit == "strip" && snapshot.UnitsPerBox < 2 {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_sale_unit", "message": "وحدة البيع غير مسموحة لأحد الأصناف"})
                        return
                }
                snapshots[i] = snapshot
                unitPrice := snapshot.effectiveUnitPrice(item.SaleUnit)
                lineTotals[i] = unitPrice.MulQty(item.Quantity)
                if (item.ExpectedUnitPricePiastres != nil && *item.ExpectedUnitPricePiastres != int64(unitPrice)) ||
                        (item.ExpectedLineTotalPiastres != nil && *item.ExpectedLineTotalPiastres != int64(lineTotals[i])) {
                        mismatches = append(mismatches, gin.H{
                                "index":                    i,
                                "pharmacy_product_id":      item.PharmacyProductID,
                                "sale_unit":                item.SaleUnit,
                                "quantity":                 item.Quantity,
                                "unit_price_piastres":      unitPrice,
                                "line_total_piastres":      lineTotals[i],
                        })
                        continue
                }
        }
        if len(mismatches) > 0 {
                c.JSON(http.StatusConflict, gin.H{
                        "error":   "price_changed",
                        "message": "أسعار بعض الأصناف تغيرت، راجع الفاتورة واعتمدها مرة أخرى",
                        "data":    gin.H{"items": mismatches},
                })
                return
        }

        // Phase 2: persist the invoice.
        var saleID string
        insertErr := tx.QueryRow(c.Request.Context(), `
                INSERT INTO sales (pharmacy_id, branch_id, employee_id, company_user_id, idempotency_key)
                VALUES ($1, $2, NULLIF($3, '')::uuid, NULLIF($4, '')::uuid, NULLIF($5, ''))
                ON CONFLICT (pharmacy_id, idempotency_key) WHERE idempotency_key IS NOT NULL
                DO NOTHING
                RETURNING id::text
        `, principal.PharmacyID, branchID, employeeID, companyUserID, request.IdempotencyKey).Scan(&saleID)
        if errors.Is(insertErr, pgx.ErrNoRows) && request.IdempotencyKey != "" {
                // A concurrent retry of the same checkout won the race.
                var existingID string
                var existingTotal money.Piastres
                if err := tx.QueryRow(c.Request.Context(), `
                        SELECT id::text, total_amount::int8 FROM sales
                        WHERE pharmacy_id = $1 AND idempotency_key = $2
                `, principal.PharmacyID, request.IdempotencyKey).Scan(&existingID, &existingTotal); err == nil {
                        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                                "sale_id": existingID, "total_amount_piastres": existingTotal, "replayed": true,
                        }})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر إنشاء الفاتورة"})
                return
        }
        if insertErr != nil {
                log.Printf("[POS] sale insert failed: %v", insertErr)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر إنشاء الفاتورة"})
                return
        }

        var total money.Piastres
        for i, item := range request.Items {
                if err := sellPOSItem(c.Request.Context(), tx, principal, branchID, saleID, item, snapshots[i], lineTotals[i]); err != nil {
                        if errors.Is(err, errPOSSaleInsufficientStock) {
                                c.JSON(http.StatusConflict, gin.H{"error": "insufficient_stock", "message": "الكمية المطلوبة غير متاحة في المخزون"})
                                return
                        }
                        log.Printf("[POS] sale item failed (product=%s unit=%s qty=%d): %v", item.PharmacyProductID, item.SaleUnit, item.Quantity, err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر تسجيل حركة البيع"})
                        return
                }
                total = total.Add(lineTotals[i])
        }
        if _, err := tx.Exec(c.Request.Context(), `UPDATE sales SET total_amount = $2 WHERE id = $1`, saleID, total); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر حفظ إجمالي الفاتورة"})
                return
        }
        if err := tx.Commit(c.Request.Context()); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر تأكيد الفاتورة"})
                return
        }
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "sale_id": saleID, "total_amount_piastres": total, "replayed": false,
        }})
}

// sellPOSItem fulfills one sale line from batches using FEFO. The line's
// revenue is exact (quantity x unit price in integer piastres); when the
// line spans several batches, the line total is allocated across the batch
// rows with the largest-remainder method so the rows always sum to the line
// total exactly.
func sellPOSItem(
        ctx context.Context,
        tx pgx.Tx,
        principal *auth.Principal,
        branchID, saleID string,
        item posSaleItemRequest,
        snapshot posPricingSnapshot,
        lineTotal money.Piastres,
) error {
        unitFactor := int64(1)
        if item.SaleUnit == "box" {
                unitFactor = snapshot.UnitsPerBox
        }
        unitPrice := snapshot.effectiveUnitPrice(item.SaleUnit)
        employeeID, companyUserID := actorIDs(principal)
        requiredBase := item.Quantity * unitFactor

        rows, err := tx.Query(ctx, `
                SELECT ib.id::text, ROUND(ib.quantity)::int8, ib.unit::text, ib.cost_per_unit::int8
                FROM inventory_batches ib
                WHERE ib.pharmacy_product_id = $1 AND ib.branch_id = $2
                  AND ib.is_quarantined = false AND ib.quantity > 0
                ORDER BY ib.expiry_date NULLS LAST, ib.received_date, ib.created_at
                FOR UPDATE
        `, item.PharmacyProductID, branchID)
        if err != nil {
                log.Printf("[POS] batch query failed (product=%s branch=%s): %v", item.PharmacyProductID, branchID, err)
                return err
        }
        // pgx: the tx connection is busy while query rows are open. Buffer the
        // batches and release the rows BEFORE running the sale INSERTs on the
        // same transaction, otherwise every checkout fails with "conn busy".
        type batchStock struct {
                id          string
                available   int64
                baseUnit    string
                costPerUnit money.Piastres
        }
        batches := make([]batchStock, 0)
        for rows.Next() {
                var b batchStock
                if err := rows.Scan(&b.id, &b.available, &b.baseUnit, &b.costPerUnit); err != nil {
                        log.Printf("[POS] batch scan failed: %v", err)
                        rows.Close()
                        return err
                }
                batches = append(batches, b)
        }
        if err := rows.Err(); err != nil {
                log.Printf("[POS] batch rows failed: %v", err)
                rows.Close()
                return err
        }
        rows.Close()

        remaining := requiredBase
        takes := make([]int64, 0, len(batches))
        for _, b := range batches {
                if remaining <= 0 {
                        break
                }
                take := b.available
                if take > remaining {
                        take = remaining
                }
                if take <= 0 {
                        continue
                }
                takes = append(takes, take)
                remaining -= take
        }
        if remaining > 0 {
                return errPOSSaleInsufficientStock
        }

        amounts := money.Allocate(lineTotal, takes)
        for i, take := range takes {
                b := batches[i]
                after := b.available - take
                costAmount := b.costPerUnit.MulQty(take)
                if _, err := tx.Exec(ctx, `
                        INSERT INTO sale_items (
                                sale_id, pharmacy_product_id, batch_id, sale_unit,
                                quantity, base_quantity, unit_price, unit_cost,
                                amount_piastres, cost_amount_piastres
                        ) VALUES ($1, $2, $3, $4, $5, $5, $6, $7, $8, $9)
                `, saleID, item.PharmacyProductID, b.id, item.SaleUnit,
                        take, unitPrice, b.costPerUnit, amounts[i], costAmount); err != nil {
                        return err
                }
                if _, err := tx.Exec(ctx, `
                        INSERT INTO stock_movements (
                                batch_id, movement_type, quantity, unit, reference_type,
                                reference_id, quantity_before, quantity_after, unit_cost,
                                total_cost, created_by, created_by_company_user_id, reason
                        ) VALUES ($1, 'sale'::movement_type, $2, $3::unit_type, 'sale', $4,
                                  $5, $6, $7, $8, NULLIF($9, '')::uuid, NULLIF($10, '')::uuid, 'pos_sale')
                `, b.id, -take, b.baseUnit, saleID, b.available, after, b.costPerUnit, -int64(costAmount), employeeID, companyUserID); err != nil {
                        return err
                }
                if _, err := tx.Exec(ctx, `UPDATE inventory_batches SET quantity = $2, updated_at = NOW() WHERE id = $1`, b.id, after); err != nil {
                        return err
                }
        }
        if _, err := tx.Exec(ctx, `
                UPDATE pharmacy_products SET last_sold_at = NOW(), updated_at = NOW() WHERE id = $1
        `, item.PharmacyProductID); err != nil {
                return err
        }
        return nil
}

func branchForPrincipal(c *gin.Context, tx pgx.Tx, principal *auth.Principal) (string, error) {
        if principal.BranchID != "" {
                return principal.BranchID, nil
        }
        return findBranchWithQuery(c, tx.QueryRow, principal.PharmacyID)
}

func (h *Handler) findBranch(c *gin.Context, principal *auth.Principal) (string, error) {
        if principal.BranchID != "" {
                return principal.BranchID, nil
        }
        return findBranchWithQuery(c, h.db.QueryRow, principal.PharmacyID)
}

func findBranchWithQuery(c *gin.Context, queryRow func(context.Context, string, ...interface{}) pgx.Row, pharmacyID string) (string, error) {
        var branchID string
        err := queryRow(c.Request.Context(), `
                SELECT id::text FROM branches
                WHERE pharmacy_id = $1 AND is_active = true
                ORDER BY is_main_branch DESC, created_at
                LIMIT 1
        `, pharmacyID).Scan(&branchID)
        return branchID, err
}

func actorIDs(principal *auth.Principal) (employeeID, companyUserID string) {
        if principal == nil {
                return "", ""
        }
        if principal.Type == auth.EmployeePrincipal {
                return principal.ID, ""
        }
        if principal.Type == auth.CompanyUserPrincipal {
                return "", principal.ID
        }
        return "", ""
}
