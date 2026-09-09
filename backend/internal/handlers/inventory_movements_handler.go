package handlers

// Stock movements log (سجل حركات المخزون).
//
// Read-only audit view over stock_movements — the single source of truth
// for every quantity change (purchase, sale, customer return, supplier
// return, adjustments, transfers, write-offs, ...).
//
// Scoping: the pharmacy id always comes from the session principal, never
// from the client. Quantities are signed base units (+ in / - out) and are
// served as float8 because the column is NUMERIC(12,4).

import (
        "log"
        "net/http"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
)

// movementTypesWhitelist guards the enum filter against arbitrary input.
var movementTypesWhitelist = map[string]bool{
        "purchase":             true,
        "sale":                 true,
        "return_to_supplier":   true,
        "return_from_customer": true,
        "adjustment":           true,
        "transfer_in":          true,
        "transfer_out":         true,
        "expiry_writeoff":      true,
        "damage_writeoff":      true,
        "theft_loss":           true,
        "production_input":     true,
        "production_output":    true,
}

const movementsMaxLimit = 200

// ListPharmacyStockMovements GET /api/v1/pharmacy/inventory/movements
// Query: type, search, from, to (YYYY-MM-DD), direction (in|out), limit, offset
func (h *Handler) ListPharmacyStockMovements(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }

        limit, offset := parseLimitOffsetMovements(c)

        movType := strings.TrimSpace(c.Query("type"))
        if movType != "" && !movementTypesWhitelist[movType] {
                c.JSON(http.StatusBadRequest, gin.H{
                        "error":   "invalid_movement_type",
                        "message": "نوع الحركة غير معروف",
                })
                return
        }

        search := strings.TrimSpace(c.Query("search"))

        direction := strings.TrimSpace(c.Query("direction"))
        if direction != "" && direction != "in" && direction != "out" {
                c.JSON(http.StatusBadRequest, gin.H{
                        "error":   "invalid_direction",
                        "message": "اتجاه الحركة يجب أن يكون in أو out",
                })
                return
        }

        fromTime, toTime, ok := parseMovementDateRange(c)
        if !ok {
                return
        }

        total := 0
        countErr := h.db.QueryRow(c.Request.Context(), `
                SELECT COUNT(*)::int
                FROM stock_movements sm
                JOIN inventory_batches ib ON ib.id = sm.batch_id
                JOIN pharmacy_products pp ON pp.id = ib.pharmacy_product_id
                JOIN global_products gp ON gp.id = pp.global_product_id
                WHERE pp.pharmacy_id = $1
                  AND ($2 = '' OR sm.movement_type::text = $2)
                  AND (
                      $3 = ''
                      OR gp.name ILIKE '%' || $3 || '%'
                      OR gp.generic_name ILIKE '%' || $3 || '%'
                      OR ib.batch_number ILIKE '%' || $3 || '%'
                  )
                  AND ($4::timestamptz IS NULL OR sm.created_at >= $4)
                  AND ($5::timestamptz IS NULL OR sm.created_at < $5)
                  AND ($6 = '' OR ($6 = 'in' AND sm.quantity > 0) OR ($6 = 'out' AND sm.quantity < 0))
        `, pharmacyID, movType, search, fromTime, toTime, direction).Scan(&total)
        if countErr != nil {
                log.Printf("[MOVEMENTS] count failed: %v", countErr)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "movements_query_failed", "message": "تعذر قراءة سجل حركات المخزون"})
                return
        }

        rows, err := h.db.Query(c.Request.Context(), `
                SELECT sm.id::text,
                       sm.created_at,
                       sm.movement_type::text,
                       sm.quantity::float8,
                       sm.unit::text,
                       gp.name,
                       gp.generic_name,
                       ib.batch_number,
                       b.name,
                       COALESCE(
                           NULLIF(TRIM(COALESCE(e.display_name, '')), ''),
                           NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''),
                           NULLIF(TRIM(COALESCE(cu.display_name, '')), ''),
                           NULLIF(TRIM(cu.first_name || ' ' || cu.last_name), '')
                       ),
                       sm.reference_type,
                       sm.reason,
                       sm.notes,
                       sm.quantity_after::float8
                FROM stock_movements sm
                JOIN inventory_batches ib ON ib.id = sm.batch_id
                JOIN pharmacy_products pp ON pp.id = ib.pharmacy_product_id
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN branches b ON b.id = ib.branch_id
                LEFT JOIN employees e ON e.id = sm.created_by
                LEFT JOIN company_users cu ON cu.id = sm.created_by_company_user_id
                WHERE pp.pharmacy_id = $1
                  AND ($2 = '' OR sm.movement_type::text = $2)
                  AND (
                      $3 = ''
                      OR gp.name ILIKE '%' || $3 || '%'
                      OR gp.generic_name ILIKE '%' || $3 || '%'
                      OR ib.batch_number ILIKE '%' || $3 || '%'
                  )
                  AND ($4::timestamptz IS NULL OR sm.created_at >= $4)
                  AND ($5::timestamptz IS NULL OR sm.created_at < $5)
                  AND ($6 = '' OR ($6 = 'in' AND sm.quantity > 0) OR ($6 = 'out' AND sm.quantity < 0))
                ORDER BY sm.created_at DESC, sm.id DESC
                LIMIT $7 OFFSET $8
        `, pharmacyID, movType, search, fromTime, toTime, direction, limit, offset)
        if err != nil {
                log.Printf("[MOVEMENTS] list failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "movements_query_failed", "message": "تعذر قراءة سجل حركات المخزون"})
                return
        }
        defer rows.Close()

        movements := make([]gin.H, 0, limit)
        for rows.Next() {
                var (
                        id            string
                        createdAt     time.Time
                        movTypeDB     string
                        quantity      float64
                        unit          string
                        productName   string
                        genericName   *string
                        batchNumber   *string
                        branchName    *string
                        actorName     *string
                        referenceType *string
                        reason        *string
                        notes         *string
                        quantityAfter *float64
                )
                if err := rows.Scan(&id, &createdAt, &movTypeDB, &quantity, &unit,
                        &productName, &genericName, &batchNumber, &branchName, &actorName,
                        &referenceType, &reason, &notes, &quantityAfter); err != nil {
                        log.Printf("[MOVEMENTS] scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "movements_query_failed", "message": "تعذر قراءة سجل حركات المخزون"})
                        return
                }
                movements = append(movements, gin.H{
                        "id":             id,
                        "created_at":     createdAt,
                        "movement_type":  movTypeDB,
                        "quantity":       quantity,
                        "unit":           unit,
                        "product_name":   productName,
                        "generic_name":   genericName,
                        "batch_number":   batchNumber,
                        "branch_name":    branchName,
                        "actor_name":     actorName,
                        "reference_type": referenceType,
                        "reason":         reason,
                        "notes":          notes,
                        "quantity_after": quantityAfter,
                })
        }
        if err := rows.Err(); err != nil {
                log.Printf("[MOVEMENTS] rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "movements_query_failed", "message": "تعذر قراءة سجل حركات المخزون"})
                return
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "movements": movements,
                "total":     total,
        }})
}

func parseLimitOffsetMovements(c *gin.Context) (int, int) {
        limit := 50
        if raw := strings.TrimSpace(c.Query("limit")); raw != "" {
                if v := parseIntInRange(raw, 1, movementsMaxLimit); v > 0 {
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

// parseMovementDateRange reads from/to (YYYY-MM-DD). `to` is inclusive.
func parseMovementDateRange(c *gin.Context) (*time.Time, *time.Time, bool) {
        fromRaw := strings.TrimSpace(c.Query("from"))
        toRaw := strings.TrimSpace(c.Query("to"))

        var from, to *time.Time
        if fromRaw != "" {
                parsed, err := time.Parse("2006-01-02", fromRaw)
                if err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_from_date", "message": "تاريخ البداية غير صحيح (المتوقع YYYY-MM-DD)"})
                        return nil, nil, false
                }
                from = &parsed
        }
        if toRaw != "" {
                parsed, err := time.Parse("2006-01-02", toRaw)
                if err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_to_date", "message": "تاريخ النهاية غير صحيح (المتوقع YYYY-MM-DD)"})
                        return nil, nil, false
                }
                inclusiveEnd := parsed.AddDate(0, 0, 1) // exclusive upper bound → inclusive day
                to = &inclusiveEnd
        }
        return from, to, true
}
