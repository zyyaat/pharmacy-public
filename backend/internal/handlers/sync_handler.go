package handlers

// GET /pharmacy/sync?since=<RFC3339|epoch-ms> — delta sync for the mobile
// offline cache (smart synchronization).
//
// PROBLEM IT SOLVES: the mobile offline cache is a read-through response
// cache; the prefetch service used to re-download whole lists (inventory,
// customers, 3 sale pages, 2 movement pages, the report) on every warm and
// overwrite the same cache keys. Opening the app on the internet therefore
// re-transferred data the device already had, and server-side deletions
// never reached the device. This endpoint returns ONLY what changed since
// the caller's cursor (server clock), plus tombstoned deletions, in row
// shapes identical to the regular list endpoints (see sync_rows.go) so the
// client can merge straight into its cached bodies.
//
// CONTRACT:
//   - GET /pharmacy/sync            (no since) → {"server_time"} only. The
//     client calls this once after a full prefetch so the cursor is born
//     from the SERVER clock, never the device clock (skew-proof cursors).
//   - GET /pharmacy/sync?since=T    → {"server_time", sections...} where a
//     section appears only if the principal may read it (same permission
//     keys as the underlying list endpoints):
//       inventory  {items, deleted_ids, overflow}   (inventory.view)
//       customers  {items, deleted_ids, overflow}   (customers.view)
//       sales      {items, deleted_ids, overflow}   (sales.view)
//       movements  {items, deleted_ids}             (inventory.movements.view)
//   - Each section returns at most its cap (same volume as the client
//     prefetches: 500/200/300/200). overflow=true means the changed-set
//     exceeded the cap — the client must fall back to a full refetch of
//     that entity instead of merging a partial delta.
//   - Deletions flow through sync_tombstones (migration 25): any future
//     delete path for a synced entity writes a tombstone in the same
//     transaction, and this endpoint surfaces it as deleted_ids.
//   - server_time is always the response's own clock reading; the client
//     stores it as its next cursor. Device clocks never feed the cursor.
//
// CHANGE DETECTION (why each predicate is sound):
//   - inventory rows (one per batch): sale/adjust paths write
//     UPDATE inventory_batches SET quantity, updated_at=NOW()
//     (product_pos_handler.go / inventory_batch_repo.go); product edits bump
//     pharmacy_products.updated_at and global_products.updated_at through
//     BEFORE UPDATE triggers (migration 2); new batches INSERT with
//     NOW(). → GREATEST(ib.updated_at, pp.updated_at, gp.updated_at) > since.
//   - sales: created_at for new invoices; updated_at (migration 25, trigger)
//     for the returns flow, which always runs UPDATE sales SET status even
//     when the status value is unchanged, so the trigger fires.
//   - customers: created_at / updated_at (migration 25) for row edits, plus
//     existence of newer credit sales or payments (balance is computed, so
//     any ledger movement must re-send the affected customer row).
//   - movements: append-only ledger → created_at > since.

import (
        "context"
        "log"
        "net/http"
        "strconv"
        "strings"
        "time"

        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/gin-gonic/gin"
)

// Caps mirror the volumes the mobile prefetch already caches, so a normal
// delta fits comfortably while pathological gaps overflow into full
// refetches instead of huge responses.
const (
        syncCapInventory = 500
        syncCapCustomers = 200
        syncCapSales     = 300
        syncCapMovements = 200
)

// tombstoneHorizon bounds the deleted_ids lookup — tombstones older than
// this are periodically prunable and cannot be honored anyway (the client
// never holds a cursor that old; a cursor that old overflows into a full
// refetch first).
const tombstoneHorizon = 30 * 24 * time.Hour

// GetPharmacySync implements GET /pharmacy/sync (see the file contract).
func (h *Handler) GetPharmacySync(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }

        now := time.Now().UTC()

        sinceRaw := strings.TrimSpace(c.Query("since"))
        if sinceRaw == "" {
                // Cursor bootstrap: no data, just the server clock. The client
                // stores this as its first cursor after a full prefetch.
                c.JSON(http.StatusOK, gin.H{"data": gin.H{"server_time": now}})
                return
        }

        since, err := parseSyncTime(sinceRaw)
        if err != nil {
                c.JSON(http.StatusBadRequest, gin.H{
                        "error":   "invalid_since",
                        "message": "معامل since يجب أن يكون وقت RFC3339 أو مللي ثانية منذ البدء",
                })
                return
        }

        data := gin.H{"server_time": now}

        // Sections are filtered by the same permission keys as their list
        // endpoints — a principal must never learn about rows it could not
        // have fetched directly.
        if h.pharmacyAllows(c, "inventory.view") {
                section, err := h.syncInventorySection(c.Request.Context(), pharmacyID, since, now)
                if err != nil {
                        log.Printf("[SYNC] inventory failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sync_failed", "message": "تعذر حساب تغييرات المخزون"})
                        return
                }
                data["inventory"] = section
        }
        if h.pharmacyAllows(c, "customers.view") {
                section, err := h.syncCustomersSection(c.Request.Context(), pharmacyID, since, now)
                if err != nil {
                        log.Printf("[SYNC] customers failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sync_failed", "message": "تعذر حساب تغييرات العملاء"})
                        return
                }
                data["customers"] = section
        }
        if h.pharmacyAllows(c, "sales.view") {
                section, err := h.syncSalesSection(c.Request.Context(), pharmacyID, since, now)
                if err != nil {
                        log.Printf("[SYNC] sales failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sync_failed", "message": "تعذر حساب تغييرات الفواتير"})
                        return
                }
                data["sales"] = section
        }
        if h.pharmacyAllows(c, "inventory.movements.view") {
                section, err := h.syncMovementsSection(c.Request.Context(), pharmacyID, since, now)
                if err != nil {
                        log.Printf("[SYNC] movements failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "sync_failed", "message": "تعذر حساب تغييرات الحركات"})
                        return
                }
                data["movements"] = section
        }

        c.JSON(http.StatusOK, gin.H{"data": data})
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

func (h *Handler) syncInventorySection(ctx context.Context, pharmacyID string, since, now time.Time) (gin.H, error) {
        // The shared column list (inventorySelectColumns) is alias-less, so the
        // changed-set detection lives in an inner query over the base tables
        // (where ib/pp/gp.updated_at are visible) and the outer read comes from
        // current_inventory alone — exactly the relation, shape, and ordering
        // the list endpoint serves.
        ids, overflow, err := h.changedInventoryBatchIDs(ctx, pharmacyID, since, syncCapInventory)
        if err != nil {
                return nil, err
        }
        if len(ids) == 0 {
                deleted, err := h.syncDeletedIDs(ctx, pharmacyID, "inventory_batch", since, now)
                if err != nil {
                        return nil, err
                }
                return gin.H{"items": []gin.H{}, "deleted_ids": deleted, "overflow": overflow}, nil
        }

        rows, err := h.db.Query(ctx, `
                SELECT `+inventorySelectColumns+`
                FROM current_inventory
                WHERE pharmacy_id = $1
                  AND batch_id = ANY($2::uuid[])
                ORDER BY product_name, expiry_date NULLS LAST
        `, pharmacyID, ids)
        if err != nil {
                return nil, err
        }
        defer rows.Close()

        items := make([]gin.H, 0, len(ids))
        for rows.Next() {
                item, err := scanInventoryRow(rows)
                if err != nil {
                        return nil, err
                }
                items = append(items, item)
        }
        if err := rows.Err(); err != nil {
                return nil, err
        }

        deleted, err := h.syncDeletedIDs(ctx, pharmacyID, "inventory_batch", since, now)
        if err != nil {
                return nil, err
        }
        return gin.H{"items": items, "deleted_ids": deleted, "overflow": overflow}, nil
}

// changedInventoryBatchIDs returns the ids of batches whose row (or any of
// its product parents) changed after the cursor, newest change first. When
// more than cap batches changed, overflow=true and only the cap most recent
// ids come back.
func (h *Handler) changedInventoryBatchIDs(ctx context.Context, pharmacyID string, since time.Time, maxRows int) ([]string, bool, error) {
        rows, err := h.db.Query(ctx, `
                SELECT ib.id::text
                FROM inventory_batches ib
                JOIN pharmacy_products pp ON pp.id = ib.pharmacy_product_id
                JOIN global_products gp ON gp.id = pp.global_product_id
                WHERE pp.pharmacy_id = $1
                  AND GREATEST(
                      COALESCE(ib.updated_at, '-infinity'::timestamptz),
                      COALESCE(pp.updated_at, '-infinity'::timestamptz),
                      COALESCE(gp.updated_at, '-infinity'::timestamptz)) > $2
                ORDER BY GREATEST(
                      COALESCE(ib.updated_at, '-infinity'::timestamptz),
                      COALESCE(pp.updated_at, '-infinity'::timestamptz),
                      COALESCE(gp.updated_at, '-infinity'::timestamptz)) DESC
                LIMIT $3
        `, pharmacyID, since, maxRows+1)
        if err != nil {
                return nil, false, err
        }
        defer rows.Close()

        ids := make([]string, 0, maxRows)
        for rows.Next() {
                var id string
                if err := rows.Scan(&id); err != nil {
                        return nil, false, err
                }
                ids = append(ids, id)
        }
        if err := rows.Err(); err != nil {
                return nil, false, err
        }

        overflow := false
        if len(ids) > maxRows {
                ids = ids[:maxRows]
                overflow = true
        }
        return ids, overflow, nil
}

func (h *Handler) syncCustomersSection(ctx context.Context, pharmacyID string, since, now time.Time) (gin.H, error) {
        // Same balance computation and row shape as ListPharmacyCustomers; the
        // affected-since predicate covers row edits AND balance drift (a credit
        // sale or a payment for this customer after the cursor).
        rows, err := h.db.Query(ctx, `
                SELECT t.id, t.name, t.phone, t.created_at, t.balance FROM (
                    SELECT c.id::text AS id, c.name::text AS name, COALESCE(c.phone::text, '') AS phone, c.created_at AS created_at,
                           `+customerBalanceExpr+` AS balance
                    FROM customers c
                    WHERE c.pharmacy_id = $1
                      AND (
                              c.created_at > $2
                           OR c.updated_at > $2
                           OR EXISTS (SELECT 1 FROM customer_payments p
                                      WHERE p.customer_id = c.id AND p.created_at > $2)
                           OR EXISTS (SELECT 1 FROM sales s
                                      WHERE s.customer_id = c.id
                                        AND (s.created_at > $2 OR s.updated_at > $2))
                      )
                ) t
                ORDER BY t.created_at DESC
                LIMIT $3
        `, pharmacyID, since, syncCapCustomers+1)
        if err != nil {
                return nil, err
        }
        defer rows.Close()

        items := make([]gin.H, 0, syncCapCustomers)
        for rows.Next() {
                item, err := scanCustomerRow(rows)
                if err != nil {
                        return nil, err
                }
                items = append(items, item)
        }
        if err := rows.Err(); err != nil {
                return nil, err
        }

        overflow := false
        if len(items) > syncCapCustomers {
                items = items[:syncCapCustomers]
                overflow = true
        }

        deleted, err := h.syncDeletedIDs(ctx, pharmacyID, "customer", since, now)
        if err != nil {
                return nil, err
        }
        return gin.H{"items": items, "deleted_ids": deleted, "overflow": overflow}, nil
}

func (h *Handler) syncSalesSection(ctx context.Context, pharmacyID string, since, now time.Time) (gin.H, error) {
        // Same columns/shape as ListPOSSales (returns attached below); changed
        // = new invoice OR status touch (returns flow always UPDATEs the row).
        rows, err := h.db.Query(ctx, `
                `+saleSummarySelectColumns+`
                WHERE s.pharmacy_id = $1
                  AND (s.created_at > $2 OR s.updated_at > $2)
                ORDER BY GREATEST(s.created_at, s.updated_at) DESC, s.invoice_number DESC
                LIMIT $3
        `, pharmacyID, since, syncCapSales+1)
        if err != nil {
                return nil, err
        }

        summaries := make([]*saleSummaryRow, 0, syncCapSales)
        saleIDs := make([]string, 0, syncCapSales)
        for rows.Next() {
                s, err := scanSaleSummaryRow(rows)
                if err != nil {
                        rows.Close()
                        return nil, err
                }
                summaries = append(summaries, s)
                saleIDs = append(saleIDs, s.ID)
        }
        rows.Close()
        if err := rows.Err(); err != nil {
                return nil, err
        }

        overflow := false
        if len(summaries) > syncCapSales {
                summaries = summaries[:syncCapSales]
                saleIDs = saleIDs[:syncCapSales]
                overflow = true
        }

        if err := attachSaleReturns(ctx, h.db, saleIDs, summaries); err != nil {
                return nil, err
        }

        payload := make([]gin.H, 0, len(summaries))
        for _, s := range summaries {
                payload = append(payload, s.Row)
        }

        deleted, err := h.syncDeletedIDs(ctx, pharmacyID, "sale", since, now)
        if err != nil {
                return nil, err
        }
        return gin.H{"items": payload, "deleted_ids": deleted, "overflow": overflow}, nil
}

func (h *Handler) syncMovementsSection(ctx context.Context, pharmacyID string, since, now time.Time) (gin.H, error) {
        // Same columns/shape as ListPharmacyStockMovements; the ledger is
        // append-only, so created_at is the whole story.
        rows, err := h.db.Query(ctx, `
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
                  AND sm.created_at > $2
                ORDER BY sm.created_at DESC, sm.id DESC
                LIMIT $3
        `, pharmacyID, since, syncCapMovements+1)
        if err != nil {
                return nil, err
        }
        defer rows.Close()

        items := make([]gin.H, 0, syncCapMovements)
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
                        return nil, err
                }
                items = append(items, gin.H{
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
                return nil, err
        }

        overflow := false
        if len(items) > syncCapMovements {
                items = items[:syncCapMovements]
                overflow = true
        }

        deleted, err := h.syncDeletedIDs(ctx, pharmacyID, "stock_movement", since, now)
        if err != nil {
                return nil, err
        }
        return gin.H{"items": items, "deleted_ids": deleted, "overflow": overflow}, nil
}

// syncDeletedIDs returns ids of synced records whose tombstones are newer
// than the cursor — the generic deletion contract (migration 25).
func (h *Handler) syncDeletedIDs(ctx context.Context, pharmacyID, entity string, since, now time.Time) ([]string, error) {
        rows, err := h.db.Query(ctx, `
                SELECT record_id::text
                FROM sync_tombstones
                WHERE pharmacy_id = $1
                  AND entity = $2
                  AND deleted_at > $3
                  AND deleted_at <= $4
                ORDER BY deleted_at ASC
        `, pharmacyID, entity, since, now)
        if err != nil {
                return nil, err
        }
        defer rows.Close()

        ids := make([]string, 0)
        for rows.Next() {
                var id string
                if err := rows.Scan(&id); err != nil {
                        return nil, err
                }
                ids = append(ids, id)
        }
        return ids, rows.Err()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// parseSyncTime accepts RFC3339 (what server_time emits and the client
// echoes back) and, defensively, epoch milliseconds.
func parseSyncTime(raw string) (time.Time, error) {
        if v, err := strconv.ParseInt(raw, 10, 64); err == nil {
                return time.UnixMilli(v).UTC(), nil
        }
        return time.Parse(time.RFC3339Nano, raw)
}

// pharmacyAnswers mirrors requirePharmacyPermission's resolution order as a
// boolean so one endpoint can filter sections per permission instead of
// aborting the whole request (owners → legacy employees with no rows →
// explicit key → pharmacy.admin).
func (h *Handler) pharmacyAllows(c *gin.Context, permissionKey string) bool {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.ID == "" {
                return false
        }
        if principal.Type == auth.CompanyUserPrincipal &&
                (principal.Role == "company_admin" || principal.Role == "company_manager") {
                return true
        }
        if principal.Type != auth.EmployeePrincipal {
                return false
        }
        keys, err := h.employeePermissionKeys(c, principal.ID)
        if err != nil {
                // Fail closed for the section (the route itself is authenticated);
                // the client still gets the other sections it is allowed to see.
                return false
        }
        if len(keys) == 0 {
                return true // legacy employees with no explicit rows keep full access
        }
        for _, key := range keys {
                if key == permissionKey || key == permissionAdminKey {
                        return true
                }
        }
        return false
}
