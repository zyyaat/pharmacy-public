package handlers

// Shared row builders for the pharmacy list endpoints and the delta-sync
// endpoint (GET /pharmacy/sync).
//
// WHY THIS FILE EXISTS: the offline delta-sync contract promises that every
// row inside /pharmacy/sync is byte-shape identical to the same row inside
// the regular list endpoints (GET /pharmacy/inventory, /pharmacy/customers,
// /pharmacy/pos/sales, /pharmacy/inventory/movements). The mobile client
// merges sync rows straight into cached list bodies — any column drift
// between the two would silently corrupt the offline cache. So the column
// lists, the scans, and the returns attachment live HERE, once, and both
// the list handlers and the sync handler call them.

import (
	"context"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

// ---------------------------------------------------------------------------
// Inventory rows (current_inventory — one row per batch)
// ---------------------------------------------------------------------------

// inventorySelectColumns is the SELECT column list shared by
// GetPharmacyInventory (full list) and syncInventory (delta). The scan
// order below MUST match it exactly.
const inventorySelectColumns = `
       batch_id::text, pharmacy_product_id::text, global_product_id::text,
       COALESCE(product_name::text, ''),
       COALESCE(generic_name::text, ''), COALESCE(brand_name::text, ''), COALESCE(barcode::text, ''),
       COALESCE(dosage_form::text, ''), COALESCE(strength::text, ''),
       COALESCE(batch_number::text, ''), COALESCE(unit::text, ''),
       ROUND(quantity)::int8, cost_per_unit::int8, total_cost::int8,
       expiry_date, days_until_expiry, selling_price::int8, COALESCE(partial_selling_price::int8, 0),
       COALESCE(packaging_type::text, ''), COALESCE(units_per_box::int8, 1), ROUND(min_stock_level)::int8,
       COALESCE(branch_name::text, ''), COALESCE(status::text, 'normal')`

// scanInventoryRow scans one current_inventory row (in the exact order of
// inventorySelectColumns) and builds the JSON map the mobile/web clients
// consume.
func scanInventoryRow(row pgx.Row) (gin.H, error) {
	var (
		batchID, pharmacyProductID, globalProductID, name, dosageForm, batchNumber, unit, status string
		genericName, brandName, barcode, strength, branchName, expiryDate, daysUntilExpiry       interface{}
		quantity, minStockLevel                                                                  int64
		costPerUnit, totalCost, sellingPrice, partialSellingPrice                                int64
		packagingType                                                                            string
		unitsPerBox                                                                              int64
	)
	if err := row.Scan(
		&batchID, &pharmacyProductID, &globalProductID, &name,
		&genericName, &brandName, &barcode, &dosageForm, &strength,
		&batchNumber, &unit, &quantity, &costPerUnit, &totalCost,
		&expiryDate, &daysUntilExpiry, &sellingPrice, &partialSellingPrice,
		&packagingType, &unitsPerBox, &minStockLevel,
		&branchName, &status,
	); err != nil {
		return nil, err
	}
	return gin.H{
		"batch_id": batchID, "pharmacy_product_id": pharmacyProductID,
		"global_product_id": globalProductID, "product_name": name,
		"generic_name": genericName, "brand_name": brandName, "barcode": barcode,
		"dosage_form": dosageForm, "strength": strength, "batch_number": batchNumber,
		"unit": unit, "quantity": quantity, "cost_per_unit_piastres": costPerUnit,
		"total_cost_piastres": totalCost, "expiry_date": expiryDate,
		"days_until_expiry": daysUntilExpiry, "selling_price_piastres": sellingPrice,
		"partial_selling_price_piastres": partialSellingPrice, "packaging_type": packagingType,
		"units_per_box": unitsPerBox, "min_stock_level": minStockLevel,
		"branch_name": branchName, "status": status,
	}, nil
}

// ---------------------------------------------------------------------------
// Customer rows (pharmacy-scoped customer accounts with computed balance)
// ---------------------------------------------------------------------------

// customerBalanceExpr is the balance subquery shared by ListPharmacyCustomers
// and syncCustomers: Σ(credit sales − their returns) − Σ(payments), in
// piastres. It reads the parameter placeholders as $N with the offsets given
// by the caller through customerBalanceExprOffsets.
const customerBalanceExpr = `
                       COALESCE((
                           SELECT SUM(s.total_amount - COALESCE(r.total, 0))::int8
                           FROM sales s
                           LEFT JOIN (
                               SELECT sale_id, SUM(total_amount_piastres) AS total
                               FROM sale_returns
                               GROUP BY sale_id
                           ) r ON r.sale_id = s.id
                           WHERE s.customer_id = c.id AND s.payment_type = 'credit'
                       ), 0)
                       - COALESCE((
                           SELECT SUM(p.amount)::int8
                           FROM customer_payments p
                           WHERE p.customer_id = c.id
                       ), 0)`

// scanCustomerRow scans one customer list row (id, name, phone, created_at,
// balance) and builds the JSON map the clients consume.
func scanCustomerRow(row pgx.Row) (gin.H, error) {
	var id, name, phone string
	var createdAt time.Time
	var balance interface{} // money.Piastres (int64) — scanned generically
	if err := row.Scan(&id, &name, &phone, &createdAt, &balance); err != nil {
		return nil, err
	}
	return gin.H{
		"id":                id,
		"name":              name,
		"phone":             phone,
		"balance_piastres":  balance,
		"created_at":        createdAt,
	}, nil
}

// ---------------------------------------------------------------------------
// Sale summary rows (POS sales list — one row per invoice + attached returns)
// ---------------------------------------------------------------------------

// saleSummarySelectColumns is the SELECT column list shared by ListPOSSales
// and syncSales. The scan order below MUST match it exactly. The caller
// supplies its own WHERE/ORDER/LIMIT.
const saleSummarySelectColumns = `
                SELECT s.id::text,
                       s.invoice_number::int8,
                       s.status::text,
                       s.total_amount::int8,
                       s.created_at,
                       COALESCE(s.payment_type::text, 'cash'),
                       COALESCE(c.name::text, ''),
                       COALESCE(s.discount_amount::int8, 0),
                       (SELECT COUNT(DISTINCT si.pharmacy_product_id) FROM sale_items si WHERE si.sale_id = s.id)::int8,
                       (SELECT ROUND(COALESCE(SUM(si.quantity), 0))::int8 FROM sale_items si WHERE si.sale_id = s.id),
                       (SELECT COALESCE(SUM(r.total_amount_piastres), 0)::int8 FROM sale_returns r WHERE r.sale_id = s.id)
                FROM sales s
                LEFT JOIN customers c ON c.id = s.customer_id`

type saleSummaryRow struct {
	Row gin.H
	ID  string
}

// scanSaleSummaryRow scans one sale summary row and builds the JSON map the
// clients consume (returns attached later via attachSaleReturns).
func scanSaleSummaryRow(row pgx.Row) (*saleSummaryRow, error) {
	var (
		id, status             string
		invoiceNumber          int64
		totalAmount            interface{} // money.Piastres
		createdAt              time.Time
		paymentType            string
		customerName           string
		discountAmount         int64
		productsCount          int64
		totalQuantityBase      int64
		returnedAmountPiastres int64
	)
	if err := row.Scan(&id, &invoiceNumber, &status, &totalAmount, &createdAt,
		&paymentType, &customerName, &discountAmount,
		&productsCount, &totalQuantityBase, &returnedAmountPiastres); err != nil {
		return nil, err
	}
	return &saleSummaryRow{
		ID: id,
		Row: gin.H{
			"id":                       id,
			"invoice_number":           invoiceNumber,
			"status":                   status,
			"total_amount_piastres":    totalAmount,
			"discount_amount_piastres": discountAmount,
			"payment_type":             paymentType,
			"customer_name":            customerName,
			"created_at":               createdAt,
			"products_count":           productsCount,
			"total_quantity_base":      totalQuantityBase,
			"returned_amount_piastres": returnedAmountPiastres,
			"returns":                  []gin.H{},
		},
	}, nil
}

// attachSaleReturns fills the "returns" array of each sale summary with the
// credit notes of the given sale ids — the exact behavior of the sales
// history list, shared with the delta-sync endpoint.
func attachSaleReturns(ctx context.Context, q interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}, saleIDs []string, summaries []*saleSummaryRow) error {
	if len(saleIDs) == 0 {
		return nil
	}
	returnRows, err := q.Query(ctx, `
                        SELECT r.sale_id::text, r.id::text, r.return_number::int8,
                               r.total_amount_piastres::int8, r.reason, r.created_at
                        FROM sale_returns r
                        WHERE r.sale_id = ANY($1::uuid[])
                        ORDER BY r.created_at ASC, r.return_number ASC
                `, saleIDs)
	if err != nil {
		return err
	}
	defer returnRows.Close()

	bySale := make(map[string][]gin.H, len(summaries))
	for returnRows.Next() {
		var saleID, id, reason string
		var returnNumber int64
		var totalAmount interface{} // money.Piastres
		var createdAt time.Time
		if err := returnRows.Scan(&saleID, &id, &returnNumber, &totalAmount, &reason, &createdAt); err != nil {
			return err
		}
		bySale[saleID] = append(bySale[saleID], gin.H{
			"id":                    id,
			"return_number":         returnNumber,
			"total_amount_piastres": totalAmount,
			"reason":                reason,
			"created_at":            createdAt,
		})
	}
	if err := returnRows.Err(); err != nil {
		return err
	}
	for _, s := range summaries {
		if returns, ok := bySale[s.ID]; ok {
			s.Row["returns"] = returns
		}
	}
	return nil
}
