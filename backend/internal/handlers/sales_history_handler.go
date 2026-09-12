package handlers

// Sales history + POS returns (credit notes).
//
// All money in this file is money.Piastres: an integer count of piastres
// (1 EGP = 100 piastres). No floating point value ever touches an amount.
//
// Return rules (best practice, audit-safe):
//   - The original invoice is NEVER mutated; every return is its own
//     credit-note document (sale_returns) shown as a reverse invoice.
//   - Returned strips go back to the EXACT batches they were sold from
//     (sale_items.batch_id), so batch traceability is preserved.
//   - Refund amounts are computed from the sale row's remaining amount
//     with the same largest-remainder allocation used at sale time, so
//     chained partial returns always converge to the exact line amount.
//   - A client-supplied idempotency key makes retries safe; concurrent
//     returns are serialized by locking the sale row BEFORE reading the
//     already-returned aggregates (fresh snapshot after the wait).

import (
        "errors"
        "log"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5"

        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/money"
)

const (
        maxReturnQuantity  = 1_000_000
        maxReturnReasonLen = 500
        defaultSalesLimit  = 20
        maxSalesLimit      = 100
)

type posReturnRequest struct {
        Items          []posReturnItemRequest `json:"items"`
        Reason         string                 `json:"reason"`
        IdempotencyKey string                 `json:"idempotency_key"`
}

type posReturnItemRequest struct {
        SaleItemID string `json:"sale_item_id"`
        Quantity   int64  `json:"quantity"`
}

// isUUID reports whether s looks like a canonical UUID. The backend does not
// vendor a uuid package; this check keeps malformed ids away from SQL casts
// so they can be answered with a clean 4xx instead of a cast error.
func isUUID(s string) bool {
        if len(s) != 36 {
                return false
        }
        for i, r := range s {
                if i == 8 || i == 13 || i == 18 || i == 23 {
                        if r != '-' {
                                return false
                        }
                        continue
                }
                isHex := (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')
                if !isHex {
                        return false
                }
        }
        return true
}

func parseLimitOffset(c *gin.Context) (int, int) {
        limit := defaultSalesLimit
        if raw := strings.TrimSpace(c.Query("limit")); raw != "" {
                if v := parseIntInRange(raw, 1, maxSalesLimit); v > 0 {
                        limit = v
                }
        }
        offset := 0
        if raw := strings.TrimSpace(c.Query("offset")); raw != "" {
                if v := parseIntInRange(raw, 0, 1_000_000_000); v > 0 {
                        offset = v
                }
        }
        return limit, offset
}

func parseIntInRange(raw string, min, max int) int {
        var v int
        neg := false
        for i, r := range raw {
                if i == 0 && r == '-' {
                        neg = true
                        continue
                }
                if r < '0' || r > '9' {
                        return -1
                }
                v = v*10 + int(r-'0')
                if v > max {
                        return max + 1
                }
        }
        if neg || v < min {
                return -1
        }
        return v
}

// ListPOSSales returns the pharmacy's invoices, newest first, each with its
// returns (credit notes) attached so the history tab can render the reverse
// invoice directly under the invoice it reverses.
//
// Optional from/to (YYYY-MM-DD, inclusive) restrict the invoice creation date
// — used by the reports module and available to the history tab.
func (h *Handler) ListPOSSales(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        limit, offset := parseLimitOffset(c)
        search := strings.TrimSpace(c.Query("search"))
        fromRaw := strings.TrimSpace(c.Query("from"))
        toRaw := strings.TrimSpace(c.Query("to"))
        var fromDay, toDay string
        if fromRaw != "" {
                parsed, err := time.Parse("2006-01-02", fromRaw)
                if err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_from_date", "message": "تاريخ البداية غير صحيح (المتوقع YYYY-MM-DD)"})
                        return
                }
                fromDay = parsed.Format("2006-01-02")
        }
        if toRaw != "" {
                parsed, err := time.Parse("2006-01-02", toRaw)
                if err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_to_date", "message": "تاريخ النهاية غير صحيح (المتوقع YYYY-MM-DD)"})
                        return
                }
                toDay = parsed.Format("2006-01-02")
        }

        total := 0
        countErr := h.db.QueryRow(c.Request.Context(), `
                SELECT COUNT(*)::int FROM sales s
                WHERE s.pharmacy_id = $1
                  AND (
                      $2 = ''
                      OR s.invoice_number::text LIKE '%' || $2 || '%'
                      OR EXISTS (
                          SELECT 1
                          FROM sale_items si
                          JOIN pharmacy_products pp ON pp.id = si.pharmacy_product_id
                          JOIN global_products gp ON gp.id = pp.global_product_id
                          WHERE si.sale_id = s.id AND gp.name ILIKE '%' || $2 || '%'
                      )
                  )
                  AND ($3 = '' OR s.created_at::date >= $3::date)
                  AND ($4 = '' OR s.created_at::date <= $4::date)
        `, pharmacyID, search, fromDay, toDay).Scan(&total)
        if countErr != nil {
                log.Printf("[SALES] count failed: %v", countErr)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sales_query_failed", "message": "تعذر قراءة سجل البيع"})
                return
        }

        // Columns + scan + returns attachment live in sync_rows.go — shared
        // with the delta-sync endpoint so the two can never drift apart.
        rows, err := h.db.Query(c.Request.Context(), `
                `+saleSummarySelectColumns+`
                WHERE s.pharmacy_id = $1
                  AND (
                      $2 = ''
                      OR s.invoice_number::text LIKE '%' || $2 || '%'
                      OR EXISTS (
                          SELECT 1
                          FROM sale_items si
                          JOIN pharmacy_products pp ON pp.id = si.pharmacy_product_id
                          JOIN global_products gp ON gp.id = pp.global_product_id
                          WHERE si.sale_id = s.id AND gp.name ILIKE '%' || $2 || '%'
                      )
                  )
                  AND ($5 = '' OR s.created_at::date >= $5::date)
                  AND ($6 = '' OR s.created_at::date <= $6::date)
                ORDER BY s.created_at DESC, s.invoice_number DESC
                LIMIT $3 OFFSET $4
        `, pharmacyID, search, limit, offset, fromDay, toDay)
        if err != nil {
                log.Printf("[SALES] list failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sales_query_failed", "message": "تعذر قراءة سجل البيع"})
                return
        }

        sales := make([]*saleSummaryRow, 0)
        saleIDs := make([]string, 0)
        for rows.Next() {
                s, err := scanSaleSummaryRow(rows)
                if err != nil {
                        rows.Close()
                        log.Printf("[SALES] scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sales_query_failed", "message": "تعذر قراءة سجل البيع"})
                        return
                }
                sales = append(sales, s)
                saleIDs = append(saleIDs, s.ID)
        }
        rows.Close()
        if err := rows.Err(); err != nil {
                log.Printf("[SALES] rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sales_query_failed", "message": "تعذر قراءة سجل البيع"})
                return
        }

        if err := attachSaleReturns(c.Request.Context(), h.db, saleIDs, sales); err != nil {
                log.Printf("[SALES] returns list failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sales_query_failed", "message": "تعذر قراءة سجل البيع"})
                return
        }

        payload := make([]gin.H, 0, len(sales))
        for _, s := range sales {
                payload = append(payload, s.Row)
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "sales":  payload,
                "total":  total,
                "limit":  limit,
                "offset": offset,
        }})
}

// GetPOSSale returns one invoice with row-level detail (one row per batch
// line) plus everything already returned, so the UI can offer exact
// returnable quantities per row.
func (h *Handler) GetPOSSale(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        saleID := strings.TrimSpace(c.Param("sale_id"))
        if !isUUID(saleID) {
                c.JSON(http.StatusNotFound, gin.H{"error": "sale_not_found", "message": "الفاتورة غير موجودة"})
                return
        }

        var (
                id, status    string
                invoiceNumber int64
                totalAmount   money.Piastres
                createdAt     time.Time
                discountAmount     money.Piastres
                paymentType        string
                customerName       string
        )
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT s.id::text, s.invoice_number::int8, s.status::text, s.total_amount::int8, s.created_at,
                       COALESCE(s.discount_amount::int8, 0), COALESCE(s.payment_type::text, 'cash'),
                       COALESCE(c.name::text, '')
                FROM sales s
                LEFT JOIN customers c ON c.id = s.customer_id
                WHERE s.id = $1::uuid AND s.pharmacy_id = $2
        `, saleID, pharmacyID).Scan(&id, &invoiceNumber, &status, &totalAmount, &createdAt,
                &discountAmount, &paymentType, &customerName)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "sale_not_found", "message": "الفاتورة غير موجودة"})
                return
        }
        if err != nil {
                log.Printf("[SALES] detail failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_query_failed", "message": "تعذر قراءة الفاتورة"})
                return
        }

        returns := make([]gin.H, 0)
        returnRows, err := h.db.Query(c.Request.Context(), `
                SELECT r.id::text, r.return_number::int8, r.total_amount_piastres::int8,
                       r.reason, r.created_at,
                       COALESCE(
                           (SELECT SUM(ri.quantity)::int8 FROM sale_return_items ri WHERE ri.return_id = r.id), 0
                       )::int8
                FROM sale_returns r
                WHERE r.sale_id = $1::uuid
                ORDER BY r.created_at ASC, r.return_number ASC
        `, saleID)
        if err != nil {
                log.Printf("[SALES] detail returns failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_query_failed", "message": "تعذر قراءة الفاتورة"})
                return
        }
        for returnRows.Next() {
                var rid, reason string
                var returnNumber int64
                var totalReturned money.Piastres
                var createdAtReturn time.Time
                var quantityBase int64
                if err := returnRows.Scan(&rid, &returnNumber, &totalReturned, &reason, &createdAtReturn, &quantityBase); err != nil {
                        returnRows.Close()
                        log.Printf("[SALES] detail returns scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_query_failed", "message": "تعذر قراءة الفاتورة"})
                        return
                }
                returns = append(returns, gin.H{
                        "id":                    rid,
                        "return_number":         returnNumber,
                        "total_amount_piastres": totalReturned,
                        "reason":                reason,
                        "created_at":            createdAtReturn,
                        "quantity_base":         quantityBase,
                })
        }
        returnRows.Close()
        if err := returnRows.Err(); err != nil {
                log.Printf("[SALES] detail returns rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_query_failed", "message": "تعذر قراءة الفاتورة"})
                return
        }

        items := make([]gin.H, 0)
        itemRows, err := h.db.Query(c.Request.Context(), `
                SELECT si.id::text,
                       si.pharmacy_product_id::text,
                       COALESCE(gp.name::text, ''),
                       COALESCE(gp.generic_name::text, ''),
                       COALESCE(gp.strength::text, ''),
                       COALESCE(gp.barcode::text, ''),
                       COALESCE(pp.packaging_type::text, ''),
                       COALESCE(pp.units_per_box::int8, 1),
                       si.sale_unit::text,
                       COALESCE(ib.batch_number::text, ''),
                       ROUND(si.quantity)::int8,
                       si.unit_price::int8,
                       si.amount_piastres::int8,
                       COALESCE(rb.returned_qty, 0)::int8,
                       COALESCE(rb.returned_amount, 0)::int8,
                       si.sale_quantity::float8,
                       si.units_per_box_snapshot::int8
                FROM sale_items si
                JOIN pharmacy_products pp ON pp.id = si.pharmacy_product_id
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN inventory_batches ib ON ib.id = si.batch_id
                LEFT JOIN (
                    SELECT sale_item_id,
                           SUM(quantity) AS returned_qty,
                           SUM(amount_piastres) AS returned_amount
                    FROM sale_return_items
                    GROUP BY sale_item_id
                ) rb ON rb.sale_item_id = si.id
                WHERE si.sale_id = $1::uuid
                ORDER BY si.created_at, si.id
        `, saleID)
        if err != nil {
                log.Printf("[SALES] detail items failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_query_failed", "message": "تعذر قراءة الفاتورة"})
                return
        }
        for itemRows.Next() {
                var (
                        itemID, productID, name, genericName, barcode string
                        strength                                      string
                        packagingType, saleUnit, batchNumber          string
                        unitsPerBox                                   int64
                        quantityBase                                  int64
                        unitPrice, amount                             money.Piastres
                        returnedQty                                   int64
                        returnedAmount                                int64
                        saleQuantity                                  *float64
                        unitsPerBoxSnapshot                           *int64
                )
                if err := itemRows.Scan(&itemID, &productID, &name, &genericName, &strength, &barcode,
                        &packagingType, &unitsPerBox, &saleUnit, &batchNumber,
                        &quantityBase, &unitPrice, &amount, &returnedQty, &returnedAmount,
                        &saleQuantity, &unitsPerBoxSnapshot); err != nil {
                        itemRows.Close()
                        log.Printf("[SALES] detail items scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_query_failed", "message": "تعذر قراءة الفاتورة"})
                        return
                }
                items = append(items, gin.H{
                        "sale_item_id":             itemID,
                        "pharmacy_product_id":      productID,
                        "product_name":             name,
                        "generic_name":             genericName,
                        "strength":                 strength,
                        "barcode":                  barcode,
                        "packaging_type":           packagingType,
                        "units_per_box":            unitsPerBox,
                        "sale_unit":                saleUnit,
                        "batch_number":             batchNumber,
                        "quantity_base":            quantityBase,
                        "unit_price_piastres":      unitPrice,
                        "amount_piastres":          amount,
                        "returned_quantity_base":   returnedQty,
                        "returnable_quantity_base": quantityBase - returnedQty,
                        "returned_amount_piastres": returnedAmount,
                        // Quantity snapshot (Final Decision 12): NULL for rows
                        // written before migration 24 — clients fall back to the
                        // documented legacy interpretation.
                        "sale_quantity":          saleQuantity,
                        "units_per_box_snapshot": unitsPerBoxSnapshot,
                })
        }
        itemRows.Close()
        if err := itemRows.Err(); err != nil {
                log.Printf("[SALES] detail items rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_query_failed", "message": "تعذر قراءة الفاتورة"})
                return
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "sale": gin.H{
                        "id":                       id,
                        "invoice_number":           invoiceNumber,
                        "status":                   status,
                        "total_amount_piastres":    totalAmount,
                        "discount_amount_piastres": discountAmount,
                        "payment_type":             paymentType,
                        "customer_name":            customerName,
                        "created_at":               createdAt,
                        "returned_amount_piastres": returnedTotal(returns),
                        "returns":                  returns,
                },
                "items": items,
        }})
}

func returnedTotal(returns []gin.H) int64 {
        var total int64
        for _, r := range returns {
                if v, ok := r["total_amount_piastres"].(money.Piastres); ok {
                        total += int64(v)
                }
        }
        return total
}

// CreatePOSSaleReturn records a return (credit note) against an invoice.
// Accepts full or partial returns: the caller lists sale_item rows with the
// base quantity (strips) to take back from each. The invoice itself is never
// modified; its status moves to partially_returned / returned instead.
func (h *Handler) CreatePOSSaleReturn(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.PharmacyID == "" || principal.ID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_mutation_account_required", "message": "حساب مدير أو موظف صيدلية مطلوب"})
                return
        }
        saleID := strings.TrimSpace(c.Param("sale_id"))
        if !isUUID(saleID) {
                c.JSON(http.StatusNotFound, gin.H{"error": "sale_not_found", "message": "الفاتورة غير موجودة"})
                return
        }

        var request posReturnRequest
        if err := c.ShouldBindJSON(&request); err != nil || len(request.Items) == 0 || len(request.Items) > 100 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_return", "message": "يجب تحديد صنف واحد على الأقل للاسترجاع"})
                return
        }
        request.Reason = strings.TrimSpace(request.Reason)
        if len(request.Reason) > maxReturnReasonLen {
                c.JSON(http.StatusBadRequest, gin.H{"error": "reason_too_long", "message": "سبب الاسترجاع طويل جداً"})
                return
        }
        request.IdempotencyKey = strings.TrimSpace(request.IdempotencyKey)
        if request.IdempotencyKey != "" &&
                (len(request.IdempotencyKey) < 8 || len(request.IdempotencyKey) > 128) {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_idempotency_key", "message": "مفتاح إعادة المحاولة غير صالح"})
                return
        }
        seen := make(map[string]bool, len(request.Items))
        for _, item := range request.Items {
                if !isUUID(item.SaleItemID) || item.Quantity < 1 || item.Quantity > maxReturnQuantity {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_return_item", "message": "بيانات أحد أصناف الاسترجاع غير صحيحة"})
                        return
                }
                if seen[item.SaleItemID] {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "duplicate_return_item", "message": "لا يمكن تكرار نفس الصنف في طلب الاسترجاع"})
                        return
                }
                seen[item.SaleItemID] = true
        }

        employeeID, companyUserID := actorIDs(principal)

        tx, err := h.db.Begin(c.Request.Context())
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر بدء عملية الاسترجاع"})
                return
        }
        defer func() { _ = tx.Rollback(c.Request.Context()) }()
        if _, err := tx.Exec(c.Request.Context(), `
                SELECT set_config('app.current_pharmacy_id', $1, true),
                       set_config('app.current_user_id', $2, true)
        `, principal.PharmacyID, principal.ID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر إعداد نطاق الصيدلية"})
                return
        }

        // Idempotent replay: retrying the same return returns the original
        // credit note instead of double-refunding.
        if request.IdempotencyKey != "" {
                var existingID string
                var existingNumber int64
                var existingTotal money.Piastres
                err := tx.QueryRow(c.Request.Context(), `
                        SELECT r.id::text, r.return_number::int8, r.total_amount_piastres::int8
                        FROM sale_returns r
                        WHERE r.pharmacy_id = $1 AND r.idempotency_key = $2
                `, principal.PharmacyID, request.IdempotencyKey).Scan(&existingID, &existingNumber, &existingTotal)
                if err == nil {
                        saleStatus := h.saleStatusByID(c, tx, existingID)
                        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                                "return_id":             existingID,
                                "return_number":         existingNumber,
                                "total_amount_piastres": existingTotal,
                                "sale_status":           saleStatus,
                                "replayed":              true,
                        }})
                        return
                }
                if !errors.Is(err, pgx.ErrNoRows) {
                        log.Printf("[SALES] return replay check failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر التحقق من عملية الاسترجاع"})
                        return
                }
        }

        // Lock the invoice FIRST. Concurrent returns of the same invoice then
        // serialize here, and the returned-aggregates query below runs on a
        // fresh snapshot AFTER the wait, so it always sees committed returns.
        var saleInternalID, branchID string
        err = tx.QueryRow(c.Request.Context(), `
                SELECT id::text, branch_id::text
                FROM sales
                WHERE id = $1::uuid AND pharmacy_id = $2
                FOR UPDATE
        `, saleID, principal.PharmacyID).Scan(&saleInternalID, &branchID)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "sale_not_found", "message": "الفاتورة غير موجودة"})
                return
        }
        if err != nil {
                log.Printf("[SALES] return sale lock failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر قراءة الفاتورة"})
                return
        }

        type saleRow struct {
                id             string
                productID      string
                batchID        string
                quantityBase   int64
                amount         money.Piastres
                unitCost       money.Piastres
                returnedQty    int64
                returnedAmount int64
        }
        rows, err := tx.Query(c.Request.Context(), `
                SELECT si.id::text, si.pharmacy_product_id::text, si.batch_id::text,
                       ROUND(si.quantity)::int8, si.amount_piastres::int8,
                       COALESCE(si.unit_cost::int8, 0),
                       COALESCE(rb.returned_qty, 0)::int8,
                       COALESCE(rb.returned_amount, 0)::int8
                FROM sale_items si
                LEFT JOIN (
                    SELECT sale_item_id,
                           SUM(quantity) AS returned_qty,
                           SUM(amount_piastres) AS returned_amount
                    FROM sale_return_items
                    GROUP BY sale_item_id
                ) rb ON rb.sale_item_id = si.id
                WHERE si.sale_id = $1::uuid
        `, saleID)
        if err != nil {
                log.Printf("[SALES] return items read failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر قراءة أصناف الفاتورة"})
                return
        }
        itemsBySaleItem := make(map[string]*saleRow)
        allRows := make([]*saleRow, 0)
        for rows.Next() {
                var r saleRow
                if err := rows.Scan(&r.id, &r.productID, &r.batchID, &r.quantityBase, &r.amount,
                        &r.unitCost, &r.returnedQty, &r.returnedAmount); err != nil {
                        rows.Close()
                        log.Printf("[SALES] return items scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر قراءة أصناف الفاتورة"})
                        return
                }
                itemsBySaleItem[r.id] = &r
                allRows = append(allRows, &r)
        }
        rows.Close()
        if err := rows.Err(); err != nil {
                log.Printf("[SALES] return items rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر قراءة أصناف الفاتورة"})
                return
        }

        // Validate every requested quantity against what is actually returnable
        // BEFORE mutating anything, and compute the exact refund per row.
        type plannedReturn struct {
                row      *saleRow
                quantity int64
                refund   money.Piastres
        }
        planned := make([]plannedReturn, 0, len(request.Items))
        var totalRefund money.Piastres
        for _, item := range request.Items {
                row, ok := itemsBySaleItem[item.SaleItemID]
                if !ok {
                        c.JSON(http.StatusNotFound, gin.H{"error": "return_item_not_found", "message": "أحد الأصناف المطلوب استرجاعها غير موجود في هذه الفاتورة"})
                        return
                }
                returnable := row.quantityBase - row.returnedQty
                if item.Quantity > returnable {
                        c.JSON(http.StatusConflict, gin.H{
                                "error":   "return_exceeds_sold",
                                "message": "الكمية المطلوب استرجاعها أكبر من الكمية المتاحة للاسترجاع",
                                "data": gin.H{
                                        "sale_item_id":             item.SaleItemID,
                                        "returnable_quantity_base": returnable,
                                },
                        })
                        return
                }
                remainingQty := returnable
                remainingAmount := money.Piastres(row.amount) - money.Piastres(row.returnedAmount)
                if remainingAmount < 0 {
                        remainingAmount = 0
                }
                var refund money.Piastres
                if item.Quantity == remainingQty {
                        // The row is fully returned now: refund exactly what is left.
                        refund = remainingAmount
                } else {
                        // Partial return: split the remaining amount between the
                        // returned and kept strips with the largest-remainder method;
                        // the two parts always sum to the remaining amount exactly.
                        parts := money.Allocate(remainingAmount, []int64{item.Quantity, remainingQty - item.Quantity})
                        refund = parts[0]
                }
                planned = append(planned, plannedReturn{row: row, quantity: item.Quantity, refund: refund})
                totalRefund = totalRefund.Add(refund)
        }

        var returnID string
        var returnNumber int64
        insertErr := tx.QueryRow(c.Request.Context(), `
                INSERT INTO sale_returns (pharmacy_id, branch_id, sale_id, total_amount_piastres, reason, employee_id, company_user_id, idempotency_key)
                VALUES ($1, $2, $3, $4, $5, NULLIF($6, '')::uuid, NULLIF($7, '')::uuid, NULLIF($8, ''))
                RETURNING id::text, return_number::int8
        `, principal.PharmacyID, branchID, saleID, totalRefund, request.Reason, employeeID, companyUserID, request.IdempotencyKey).
                Scan(&returnID, &returnNumber)
        if insertErr != nil {
                log.Printf("[SALES] return insert failed: %v", insertErr)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر إنشاء فاتورة الاسترجاع"})
                return
        }

        responseItems := make([]gin.H, 0, len(planned))
        for _, p := range planned {
                if _, err := tx.Exec(c.Request.Context(), `
                        INSERT INTO sale_return_items (return_id, sale_item_id, pharmacy_product_id, batch_id, quantity, amount_piastres)
                        VALUES ($1, $2, $3, $4, $5, $6)
                `, returnID, p.row.id, p.row.productID, p.row.batchID, p.quantity, p.refund); err != nil {
                        log.Printf("[SALES] return item insert failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر حفظ أصناف الاسترجاع"})
                        return
                }

                // Restock into the EXACT batch the strips were sold from, and write
                // the matching movement at the original cost of that sale row so
                // inventory value is reversed consistently.
                var quantityBefore, quantityAfter int64
                var batchUnit string
                restockErr := tx.QueryRow(c.Request.Context(), `
                        UPDATE inventory_batches
                        SET quantity = quantity + $2, updated_at = NOW()
                        WHERE id = $1::uuid
                        RETURNING (ROUND(quantity) - $2)::int8, ROUND(quantity)::int8, COALESCE(unit::text, 'other')
                `, p.row.batchID, p.quantity).Scan(&quantityBefore, &quantityAfter, &batchUnit)
                if restockErr != nil {
                        log.Printf("[SALES] restock failed (batch=%s): %v", p.row.batchID, restockErr)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر إرجاع الكمية للمخزون"})
                        return
                }
                costAmount := p.row.unitCost.MulQty(p.quantity)
                if _, err := tx.Exec(c.Request.Context(), `
                        INSERT INTO stock_movements (
                                batch_id, movement_type, quantity, unit, reference_type,
                                reference_id, quantity_before, quantity_after, unit_cost,
                                total_cost, created_by, created_by_company_user_id, reason
                        ) VALUES ($1, 'return_from_customer'::movement_type, $2, $3::unit_type, 'sale_return', $4,
                                  $5, $6, $7, $8, NULLIF($9, '')::uuid, NULLIF($10, '')::uuid, 'pos_return')
                `, p.row.batchID, p.quantity, batchUnit, returnID,
                        quantityBefore, quantityAfter, p.row.unitCost, costAmount, employeeID, companyUserID); err != nil {
                        log.Printf("[SALES] return movement insert failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر تسجيل حركة الاسترجاع"})
                        return
                }

                p.row.returnedQty += p.quantity
                p.row.returnedAmount += int64(p.refund)
                responseItems = append(responseItems, gin.H{
                        "sale_item_id":    p.row.id,
                        "quantity":        p.quantity,
                        "amount_piastres": p.refund,
                })
        }

        // Recompute the invoice status from the authoritative rows.
        newStatus := "partially_returned"
        fullyReturned := true
        for _, row := range allRows {
                if row.quantityBase-row.returnedQty > 0 {
                        fullyReturned = false
                        break
                }
        }
        if fullyReturned {
                newStatus = "returned"
        }
        if _, err := tx.Exec(c.Request.Context(), `
                UPDATE sales SET status = $2 WHERE id = $1::uuid
        `, saleID, newStatus); err != nil {
                log.Printf("[SALES] status update failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر تحديث حالة الفاتورة"})
                return
        }

        if err := tx.Commit(c.Request.Context()); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "return_failed", "message": "تعذر تأكيد عملية الاسترجاع"})
                return
        }
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "return_id":             returnID,
                "return_number":         returnNumber,
                "total_amount_piastres": totalRefund,
                "sale_status":           newStatus,
                "replayed":              false,
                "items":                 responseItems,
        }})
}

// saleStatusByID reads the current status of a sale on the open transaction
// (used by the idempotent replay path of CreatePOSSaleReturn).
func (h *Handler) saleStatusByID(c *gin.Context, tx pgx.Tx, returnID string) string {
        var status string
        err := tx.QueryRow(c.Request.Context(), `
                SELECT s.status::text FROM sales s
                JOIN sale_returns r ON r.sale_id = s.id
                WHERE r.id = $1::uuid
        `, returnID).Scan(&status)
        if err != nil {
                return ""
        }
        return status
}
