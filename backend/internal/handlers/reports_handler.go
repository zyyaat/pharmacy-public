package handlers

// Read-only pharmacy reports (التقارير).
//
// Three aggregate endpoints feed the reports module:
//
//      GET /pharmacy/reports/sales?from&to      → sales KPIs, daily series, top products
//      GET /pharmacy/reports/inventory          → stock valuation, expiry buckets, alerts
//      GET /pharmacy/reports/movements?from&to  → stock movement totals by type
//
// All money is money.Piastres (integer). All dates are YYYY-MM-DD, `to` is
// inclusive. Every query is scoped by the pharmacy from the session principal —
// a pharmacy id from the query string is never trusted. Range is capped at
// 366 days so a report can never scan unbounded history.

import (
        "log"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"

        "github.com/pharmacy-os/backend/internal/money"
)

const reportsMaxRangeDays = 366

// parseReportDateRange validates from/to (YYYY-MM-DD, inclusive) with sane
// defaults (last 30 days including today, UTC — consistent with the
// dashboard's CURRENT_DATE semantics).
func parseReportDateRange(c *gin.Context) (time.Time, time.Time, bool) {
        today := time.Now().UTC().Truncate(24 * time.Hour)

        fromRaw := strings.TrimSpace(c.Query("from"))
        toRaw := strings.TrimSpace(c.Query("to"))

        from := today.AddDate(0, 0, -29)
        if fromRaw != "" {
                parsed, err := time.Parse("2006-01-02", fromRaw)
                if err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{
                                "error":   "invalid_from_date",
                                "message": "تاريخ البداية غير صحيح (المتوقع YYYY-MM-DD)",
                        })
                        return time.Time{}, time.Time{}, false
                }
                from = parsed
        }

        to := today
        if toRaw != "" {
                parsed, err := time.Parse("2006-01-02", toRaw)
                if err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{
                                "error":   "invalid_to_date",
                                "message": "تاريخ النهاية غير صحيح (المتوقع YYYY-MM-DD)",
                        })
                        return time.Time{}, time.Time{}, false
                }
                to = parsed
        }

        if to.Before(from) {
                c.JSON(http.StatusBadRequest, gin.H{
                        "error":   "invalid_date_range",
                        "message": "تاريخ النهاية يجب أن يكون بعد تاريخ البداية",
                })
                return time.Time{}, time.Time{}, false
        }
        if to.Sub(from).Hours() > reportsMaxRangeDays*24 {
                c.JSON(http.StatusBadRequest, gin.H{
                        "error":   "date_range_too_long",
                        "message": "أقصى فترة للتقرير هي سنة واحدة",
                })
                return time.Time{}, time.Time{}, false
        }
        return from, to, true
}

// GetPharmacySalesReport GET /pharmacy/reports/sales?from&to
func (h *Handler) GetPharmacySalesReport(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        from, to, ok := parseReportDateRange(c)
        if !ok {
                return
        }
        fromDate, toDate := from.Format("2006-01-02"), to.Format("2006-01-02")

        // Headline KPIs: invoices, gross, units sold.
        var invoicesCount, grossPiastres, unitsBase int64
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT
                        COUNT(*)::int8,
                        COALESCE(SUM(s.total_amount), 0)::int8,
                        COALESCE((SELECT ROUND(SUM(si.base_quantity))::int8
                                  FROM sale_items si
                                  JOIN sales s2 ON s2.id = si.sale_id
                                  WHERE s2.pharmacy_id = $1
                                    AND s2.created_at::date BETWEEN $2::date AND $3::date), 0)
                FROM sales s
                WHERE s.pharmacy_id = $1
                  AND s.created_at::date BETWEEN $2::date AND $3::date
        `, pharmacyID, fromDate, toDate).Scan(&invoicesCount, &grossPiastres, &unitsBase)
        if err != nil {
                log.Printf("[REPORTS] sales kpi failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر حساب مؤشرات المبيعات"})
                return
        }

        // Returns (credit notes) issued in the period, regardless of the invoice date.
        var returnsCount int64
        var returnedPiastres money.Piastres
        err = h.db.QueryRow(c.Request.Context(), `
                SELECT COUNT(*)::int8, COALESCE(SUM(r.total_amount_piastres), 0)::int8
                FROM sale_returns r
                JOIN sales s ON s.id = r.sale_id
                WHERE s.pharmacy_id = $1
                  AND r.created_at::date BETWEEN $2::date AND $3::date
        `, pharmacyID, fromDate, toDate).Scan(&returnsCount, &returnedPiastres)
        if err != nil {
                log.Printf("[REPORTS] sales returns failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر حساب المرتجعات"})
                return
        }

        // Daily series (RTL-friendly bar chart source), zero-filled per day.
        type dailyRow struct {
                day             string
                invoicesCount   int64
                grossPiastres   money.Piastres
                returnedPiastre money.Piastres
        }
        dailyRows := make([]dailyRow, 0)
        dailyIter, err := h.db.Query(c.Request.Context(), `
                SELECT d::date::text,
                       COALESCE((SELECT COUNT(*)::int8 FROM sales s
                                 WHERE s.pharmacy_id = $1 AND s.created_at::date = d::date), 0),
                       COALESCE((SELECT SUM(s.total_amount)::int8 FROM sales s
                                 WHERE s.pharmacy_id = $1 AND s.created_at::date = d::date), 0),
                       COALESCE((SELECT SUM(r.total_amount_piastres)::int8 FROM sale_returns r
                                 JOIN sales s ON s.id = r.sale_id
                                 WHERE s.pharmacy_id = $1 AND r.created_at::date = d::date), 0)
                FROM generate_series($2::date, $3::date, interval '1 day') d
                ORDER BY d
        `, pharmacyID, fromDate, toDate)
        if err != nil {
                log.Printf("[REPORTS] sales daily failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر حساب السلسلة اليومية"})
                return
        }
        for dailyIter.Next() {
                var row dailyRow
                if err := dailyIter.Scan(&row.day, &row.invoicesCount, &row.grossPiastres, &row.returnedPiastre); err != nil {
                        dailyIter.Close()
                        log.Printf("[REPORTS] sales daily scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر قراءة السلسلة اليومية"})
                        return
                }
                dailyRows = append(dailyRows, row)
        }
        dailyIter.Close()
        if err := dailyIter.Err(); err != nil {
                log.Printf("[REPORTS] sales daily rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر قراءة السلسلة اليومية"})
                return
        }

        // Top products by revenue in the period.
        type topProduct struct {
                ProductID   string `json:"product_id"`
                Name        string `json:"name"`
                GenericName string `json:"generic_name"`
                Quantity    int64  `json:"quantity_base"`
                Amount      int64  `json:"amount_piastres"`
        }
        topProducts := make([]topProduct, 0)
        topIter, err := h.db.Query(c.Request.Context(), `
                SELECT pp.id::text,
                       gp.name,
                       COALESCE(gp.generic_name, ''),
                       ROUND(SUM(si.base_quantity))::int8,
                       COALESCE(SUM(si.amount_piastres), 0)::int8
                FROM sale_items si
                JOIN sales s ON s.id = si.sale_id
                JOIN pharmacy_products pp ON pp.id = si.pharmacy_product_id
                JOIN global_products gp ON gp.id = pp.global_product_id
                WHERE s.pharmacy_id = $1
                  AND s.created_at::date BETWEEN $2::date AND $3::date
                GROUP BY pp.id, gp.name, gp.generic_name
                ORDER BY 5 DESC
                LIMIT 10
        `, pharmacyID, fromDate, toDate)
        if err != nil {
                log.Printf("[REPORTS] top products failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر حساب المنتجات الأكثر بيعاً"})
                return
        }
        for topIter.Next() {
                var row topProduct
                if err := topIter.Scan(&row.ProductID, &row.Name, &row.GenericName, &row.Quantity, &row.Amount); err != nil {
                        topIter.Close()
                        log.Printf("[REPORTS] top products scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر قراءة المنتجات الأكثر بيعاً"})
                        return
                }
                topProducts = append(topProducts, row)
        }
        topIter.Close()
        if err := topIter.Err(); err != nil {
                log.Printf("[REPORTS] top products rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر قراءة المنتجات الأكثر بيعاً"})
                return
        }

        gross := int64(grossPiastres)
        returned := int64(returnedPiastres)
        daily := make([]gin.H, 0, len(dailyRows))
        for _, row := range dailyRows {
                grossDay := int64(row.grossPiastres)
                returnedDay := int64(row.returnedPiastre)
                daily = append(daily, gin.H{
                        "day":               row.day,
                        "invoices_count":    row.invoicesCount,
                        "gross_piastres":    grossDay,
                        "returned_piastres": returnedDay,
                        "net_piastres":      grossDay - returnedDay,
                })
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "period": gin.H{"from": fromDate, "to": toDate},
                "sales": gin.H{
                        "invoices_count":     invoicesCount,
                        "gross_piastres":     gross,
                        "units_base":         unitsBase,
                        "returns_count":      returnsCount,
                        "returned_piastres":  returned,
                        "net_piastres":       gross - returned,
                        "avg_invoice_piastres": func() int64 {
                                if invoicesCount > 0 {
                                        return gross / invoicesCount
                                }
                                return 0
                        }(),
                },
                "daily":        daily,
                "top_products": topProducts,
        }})
}

// GetPharmacyInventoryReport GET /pharmacy/reports/inventory
func (h *Handler) GetPharmacyInventoryReport(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }

        // Headline valuation. Retail value respects strip pricing: a BOX_STRIP
        // batch is valued at its partial (strip) price, falling back to the
        // documented half-up box-price ÷ units-per-box when no strip price set.
        var batchesCount, productsCount, unitsBase, costValue, retailValue, lowStock, outOfStock int64
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT
                        COUNT(*)::int8,
                        COUNT(DISTINCT pharmacy_product_id)::int8,
                        ROUND(COALESCE(SUM(quantity), 0))::int8,
                        COALESCE(SUM(total_cost), 0)::int8,
                        COALESCE(SUM(
                                CASE WHEN packaging_type = 'BOX_STRIP'
                                        THEN quantity * COALESCE(
                                                partial_selling_price::numeric,
                                                ROUND(selling_price::numeric / NULLIF(units_per_box, 0)))
                                        ELSE quantity * selling_price
                                END
                        ), 0)::int8,
                        COUNT(*) FILTER (WHERE quantity > 0 AND quantity <= min_stock_level)::int8,
                        COUNT(*) FILTER (WHERE quantity <= 0)::int8
                FROM current_inventory
                WHERE pharmacy_id = $1
        `, pharmacyID).Scan(&batchesCount, &productsCount, &unitsBase, &costValue, &retailValue, &lowStock, &outOfStock)
        if err != nil {
                log.Printf("[REPORTS] inventory kpi failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر حساب مؤشرات المخزون"})
                return
        }

        // Expiry buckets (counts + value at risk within 90 days).
        var expiredCount, expiring30, expiring60, expiring90, expiredValue, expiringValue int64
        err = h.db.QueryRow(c.Request.Context(), `
                SELECT
                        COUNT(*) FILTER (WHERE expiry_date < CURRENT_DATE)::int8,
                        COUNT(*) FILTER (WHERE expiry_date >= CURRENT_DATE AND expiry_date <= CURRENT_DATE + 30)::int8,
                        COUNT(*) FILTER (WHERE expiry_date > CURRENT_DATE + 30 AND expiry_date <= CURRENT_DATE + 60)::int8,
                        COUNT(*) FILTER (WHERE expiry_date > CURRENT_DATE + 60 AND expiry_date <= CURRENT_DATE + 90)::int8,
                        COALESCE(SUM(total_cost) FILTER (WHERE expiry_date < CURRENT_DATE), 0)::int8,
                        COALESCE(SUM(total_cost) FILTER (WHERE expiry_date >= CURRENT_DATE AND expiry_date <= CURRENT_DATE + 90), 0)::int8
                FROM current_inventory
                WHERE pharmacy_id = $1
        `, pharmacyID).Scan(&expiredCount, &expiring30, &expiring60, &expiring90, &expiredValue, &expiringValue)
        if err != nil {
                log.Printf("[REPORTS] expiry buckets failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر حساب مجموعات الصلاحية"})
                return
        }

        // Low-stock watchlist (most urgent first). Out-of-stock rows are counted
        // separately, so the list matches the low_stock_count KPI.
        lowItems, err := h.inventoryAlertItems(c, pharmacyID, `
                SELECT COALESCE(gp.name::text, ''), COALESCE(gp.generic_name::text, ''),
                       COALESCE(ci.batch_number::text, ''), COALESCE(b.name::text, ''),
                       ROUND(ci.quantity)::int8, ROUND(ci.min_stock_level)::int8,
                       ci.selling_price::int8, ci.status::text, NULL::date
                FROM current_inventory ci
                JOIN pharmacy_products pp ON pp.id = ci.pharmacy_product_id
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN branches b ON b.id = ci.branch_id
                WHERE ci.pharmacy_id = $1 AND ci.quantity > 0 AND ci.quantity <= ci.min_stock_level
                ORDER BY (ci.quantity - ci.min_stock_level) ASC, ci.quantity ASC, gp.name
                LIMIT 20
        `)
        if err != nil {
                log.Printf("[REPORTS] low stock list failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر قراءة قائمة النواقص"})
                return
        }

        // Nearest expiry watchlist (within 90 days or already expired). Days are
        // computed from expiry_date directly — the stored days_until_expiry column
        // is not reliably maintained.
        expiringItems, err := h.inventoryAlertItems(c, pharmacyID, `
                SELECT COALESCE(gp.name::text, ''), COALESCE(gp.generic_name::text, ''),
                       COALESCE(ci.batch_number::text, ''), COALESCE(b.name::text, ''),
                       ROUND(ci.quantity)::int8, (ci.expiry_date - CURRENT_DATE)::int8,
                       ci.selling_price::int8, ci.status::text, ci.expiry_date::date
                FROM current_inventory ci
                JOIN pharmacy_products pp ON pp.id = ci.pharmacy_product_id
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN branches b ON b.id = ci.branch_id
                WHERE ci.pharmacy_id = $1 AND ci.expiry_date IS NOT NULL
                  AND ci.expiry_date <= CURRENT_DATE + 90
                ORDER BY ci.expiry_date ASC, gp.name
                LIMIT 20
        `)
        if err != nil {
                log.Printf("[REPORTS] expiring list failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر قراءة قائمة الصلاحيات"})
                return
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "totals": gin.H{
                        "batches_count":       batchesCount,
                        "products_count":      productsCount,
                        "units_base":          unitsBase,
                        "cost_value_piastres": costValue,
                        "retail_value_piastres": retailValue,
                        "low_stock_count":     lowStock,
                        "out_of_stock_count":  outOfStock,
                },
                "expiry": gin.H{
                        "expired_count":          expiredCount,
                        "expiring_30_count":      expiring30,
                        "expiring_60_count":      expiring60,
                        "expiring_90_count":      expiring90,
                        "expired_value_piastres": expiredValue,
                        "expiring_value_piastres": expiringValue,
                },
                "low_stock_items":  lowItems,
                "expiring_items":   expiringItems,
        }})
}

// inventoryAlertItems scans the name/batch/branch/quantity/threshold/price/
// status/extra-date projection shared by the low-stock and expiry watchlists.
// extra_date carries the batch expiry date for the expiry watchlist (NULL for
// the low-stock list).
func (h *Handler) inventoryAlertItems(c *gin.Context, pharmacyID, query string) ([]gin.H, error) {
        rows, err := h.db.Query(c.Request.Context(), query, pharmacyID)
        if err != nil {
                return nil, err
        }
        defer rows.Close()

        items := make([]gin.H, 0)
        for rows.Next() {
                var name, genericName, batchNumber, branchName, status string
                var quantity, threshold, sellingPrice int64
                var extraDate *time.Time
                if err := rows.Scan(&name, &genericName, &batchNumber, &branchName,
                        &quantity, &threshold, &sellingPrice, &status, &extraDate); err != nil {
                        return nil, err
                }
                item := gin.H{
                        "name":                   name,
                        "generic_name":           genericName,
                        "batch_number":           batchNumber,
                        "branch_name":            branchName,
                        "quantity":               quantity,
                        "threshold":              threshold,
                        "selling_price_piastres": sellingPrice,
                        "status":                 status,
                        "extra_date":             extraDate,
                }
                items = append(items, item)
        }
        return items, rows.Err()
}

// GetPharmacyMovementsReport GET /pharmacy/reports/movements?from&to
func (h *Handler) GetPharmacyMovementsReport(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        from, to, ok := parseReportDateRange(c)
        if !ok {
                return
        }
        fromDate, toDate := from.Format("2006-01-02"), to.Format("2006-01-02")

        rows, err := h.db.Query(c.Request.Context(), `
                SELECT sm.movement_type::text,
                       COUNT(*)::int8,
                       ROUND(COALESCE(SUM(sm.quantity) FILTER (WHERE sm.quantity > 0), 0))::int8,
                       ROUND(COALESCE(SUM(ABS(sm.quantity)) FILTER (WHERE sm.quantity < 0), 0))::int8
                FROM stock_movements sm
                JOIN inventory_batches ib ON ib.id = sm.batch_id
                JOIN pharmacy_products pp ON pp.id = ib.pharmacy_product_id
                WHERE pp.pharmacy_id = $1
                  AND sm.created_at::date BETWEEN $2::date AND $3::date
                GROUP BY sm.movement_type
                ORDER BY 2 DESC
        `, pharmacyID, fromDate, toDate)
        if err != nil {
                log.Printf("[REPORTS] movements failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر حساب ملخص الحركات"})
                return
        }
        defer rows.Close()

        byType := make([]gin.H, 0)
        var totalTransactions, totalIn, totalOut int64
        for rows.Next() {
                var movementType string
                var transactions, quantityIn, quantityOut int64
                if err := rows.Scan(&movementType, &transactions, &quantityIn, &quantityOut); err != nil {
                        log.Printf("[REPORTS] movements scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر قراءة ملخص الحركات"})
                        return
                }
                byType = append(byType, gin.H{
                        "movement_type": movementType,
                        "transactions":  transactions,
                        "quantity_in":   quantityIn,
                        "quantity_out":  quantityOut,
                })
                totalTransactions += transactions
                totalIn += quantityIn
                totalOut += quantityOut
        }
        if err := rows.Err(); err != nil {
                log.Printf("[REPORTS] movements rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "reports_query_failed", "message": "تعذر قراءة ملخص الحركات"})
                return
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "period": gin.H{"from": fromDate, "to": toDate},
                "by_type": byType,
                "totals": gin.H{
                        "transactions": totalTransactions,
                        "quantity_in":  totalIn,
                        "quantity_out": totalOut,
                },
        }})
}
