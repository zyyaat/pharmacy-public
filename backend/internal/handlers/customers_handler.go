package handlers

// Customer accounts (حسابات العملاء / البيع الآجل) + low-stock alerts.
//
// Money here is money.Piastres (integer piastres, 1 EGP = 100 piastres).
// A customer's balance is DERIVED, never stored:
//
//      balance = Σ(credit sales − their returns) − Σ(payments)
//
// so refunds of credit invoices automatically reduce the debt, and a
// payment can never disagree with the invoices it settles.
// Every query is pharmacy-scoped (explicit WHERE + RLS policies mirroring
// the sales tables, migration 19).

import (
        "context"
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

const maxCustomerNameLen = 120
const maxCustomerPhoneLen = 20
const maxPaymentNoteLen = 200

// ---------------------------------------------------------------------------
// List customers: GET /pharmacy/customers?search=
// ---------------------------------------------------------------------------

func (h *Handler) ListPharmacyCustomers(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        search := strings.TrimSpace(c.Query("search"))

        rows, err := h.db.Query(c.Request.Context(), `
                SELECT c.id::text, c.name::text, COALESCE(c.phone::text, ''), c.created_at,
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
                       ), 0)
                FROM customers c
                WHERE c.pharmacy_id = $1
                  AND ($2 = '' OR c.name ILIKE '%' || $2 || '%' OR c.phone LIKE '%' || $2 || '%')
                ORDER BY c.created_at DESC
                LIMIT 200
        `, pharmacyID, search)
        if err != nil {
                log.Printf("[CUSTOMERS] list failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة حسابات العملاء"})
                return
        }
        defer rows.Close()

        customers := make([]gin.H, 0)
        for rows.Next() {
                var id, name, phone string
                var createdAt time.Time
                var balance money.Piastres
                if err := rows.Scan(&id, &name, &phone, &createdAt, &balance); err != nil {
                        log.Printf("[CUSTOMERS] list scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة حسابات العملاء"})
                        return
                }
                customers = append(customers, gin.H{
                        "id":                id,
                        "name":              name,
                        "phone":             phone,
                        "balance_piastres":  balance,
                        "created_at":        createdAt,
                })
        }
        if err := rows.Err(); err != nil {
                log.Printf("[CUSTOMERS] list rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة حسابات العملاء"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"customers": customers}})
}

// ---------------------------------------------------------------------------
// Create customer: POST /pharmacy/customers {name, phone?}
// ---------------------------------------------------------------------------

type customerRequest struct {
        Name  string `json:"name"`
        Phone string `json:"phone"`
}

func (h *Handler) CreatePharmacyCustomer(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.PharmacyID == "" || principal.ID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_mutation_account_required", "message": "حساب مدير أو موظف صيدلية مطلوب"})
                return
        }
        var request customerRequest
        if err := c.ShouldBindJSON(&request); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_customer", "message": "بيانات العميل غير صحيحة"})
                return
        }
        name := strings.TrimSpace(request.Name)
        phone := strings.TrimSpace(request.Phone)
        if name == "" || len(name) > maxCustomerNameLen {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_customer_name", "message": "اسم العميل مطلوب (حتى 120 حرفاً)"})
                return
        }
        if len(phone) > maxCustomerPhoneLen {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_customer_phone", "message": "رقم الهاتف طويل جداً"})
                return
        }
        employeeID, _ := actorIDs(principal)

        var id string
        var createdAt time.Time
        err := h.db.QueryRow(c.Request.Context(), `
                INSERT INTO customers (pharmacy_id, name, phone, created_by)
                VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, '')::uuid)
                RETURNING id::text, created_at
        `, principal.PharmacyID, name, phone, employeeID).Scan(&id, &createdAt)
        if err != nil {
                log.Printf("[CUSTOMERS] create failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customer_create_failed", "message": "تعذر إضافة العميل"})
                return
        }
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "customer": gin.H{"id": id, "name": name, "phone": phone, "balance_piastres": 0, "created_at": createdAt},
        }})
}

// ---------------------------------------------------------------------------
// Update customer: PUT /pharmacy/customers/:id {name?, phone?}
// ---------------------------------------------------------------------------

func (h *Handler) UpdatePharmacyCustomer(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.PharmacyID == "" || principal.ID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_mutation_account_required", "message": "حساب مدير أو موظف صيدلية مطلوب"})
                return
        }
        customerID := strings.TrimSpace(c.Param("id"))
        if !isUUID(customerID) {
                c.JSON(http.StatusNotFound, gin.H{"error": "customer_not_found", "message": "العميل غير موجود"})
                return
        }
        var request customerRequest
        if err := c.ShouldBindJSON(&request); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_customer", "message": "بيانات العميل غير صحيحة"})
                return
        }
        name := strings.TrimSpace(request.Name)
        phone := strings.TrimSpace(request.Phone)
        if name == "" || len(name) > maxCustomerNameLen {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_customer_name", "message": "اسم العميل مطلوب (حتى 120 حرفاً)"})
                return
        }
        if len(phone) > maxCustomerPhoneLen {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_customer_phone", "message": "رقم الهاتف طويل جداً"})
                return
        }

        tag, err := h.db.Exec(c.Request.Context(), `
                UPDATE customers SET name = $3, phone = NULLIF($4, '')
                WHERE id = $1::uuid AND pharmacy_id = $2
        `, customerID, principal.PharmacyID, name, phone)
        if err != nil {
                log.Printf("[CUSTOMERS] update failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customer_update_failed", "message": "تعذر حفظ بيانات العميل"})
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "customer_not_found", "message": "العميل غير موجود"})
                return
        }
        c.JSON(http.StatusOK, gin.H{"data": gin.H{"customer": gin.H{"id": customerID, "name": name, "phone": phone}}})
}

// ---------------------------------------------------------------------------
// Statement: GET /pharmacy/customers/:id/statement
// Entries are merged chronologically; balance = Σ credit dues − Σ payments.
// ---------------------------------------------------------------------------

func (h *Handler) GetPharmacyCustomerStatement(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        customerID := strings.TrimSpace(c.Param("id"))
        if !isUUID(customerID) {
                c.JSON(http.StatusNotFound, gin.H{"error": "customer_not_found", "message": "العميل غير موجود"})
                return
        }

        var customerName, customerPhone string
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT name::text, COALESCE(phone::text, '') FROM customers
                WHERE id = $1::uuid AND pharmacy_id = $2
        `, customerID, pharmacyID).Scan(&customerName, &customerPhone)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "customer_not_found", "message": "العميل غير موجود"})
                return
        }
        if err != nil {
                log.Printf("[CUSTOMERS] statement read failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة كشف الحساب"})
                return
        }

        type entry struct {
                row        gin.H
                occurredAt time.Time
        }
        entries := make([]entry, 0)

        saleRows, err := h.db.Query(c.Request.Context(), `
                SELECT s.id::text, s.invoice_number::int8, s.created_at, s.total_amount::int8,
                       s.status::text,
                       COALESCE((SELECT SUM(total_amount_piastres)::int8 FROM sale_returns WHERE sale_id = s.id), 0)
                FROM sales s
                WHERE s.customer_id = $1::uuid AND s.payment_type = 'credit'
                ORDER BY s.created_at ASC
        `, customerID)
        if err != nil {
                log.Printf("[CUSTOMERS] statement sales failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة كشف الحساب"})
                return
        }
        for saleRows.Next() {
                var id, status string
                var invoiceNumber int64
                var createdAt time.Time
                var total, returned money.Piastres
                if err := saleRows.Scan(&id, &invoiceNumber, &createdAt, &total, &status, &returned); err != nil {
                        saleRows.Close()
                        log.Printf("[CUSTOMERS] statement sales scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة كشف الحساب"})
                        return
                }
                due := total - returned
                if due < 0 {
                        due = 0
                }
                entries = append(entries, entry{row: gin.H{
                        "kind":                     "credit_sale",
                        "id":                       id,
                        "invoice_number":           invoiceNumber,
                        "status":                   status,
                        "amount_piastres":          total,
                        "returned_amount_piastres": returned,
                        "due_amount_piastres":      due,
                        "created_at":               createdAt,
                }, occurredAt: createdAt})
        }
        saleRows.Close()
        if err := saleRows.Err(); err != nil {
                log.Printf("[CUSTOMERS] statement sales rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة كشف الحساب"})
                return
        }

        paymentRows, err := h.db.Query(c.Request.Context(), `
                SELECT id::text, amount::int8, COALESCE(note::text, ''), created_at
                FROM customer_payments
                WHERE customer_id = $1::uuid
                ORDER BY created_at ASC
        `, customerID)
        if err != nil {
                log.Printf("[CUSTOMERS] statement payments failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة كشف الحساب"})
                return
        }
        for paymentRows.Next() {
                var id, note string
                var createdAt time.Time
                var amount money.Piastres
                if err := paymentRows.Scan(&id, &amount, &note, &createdAt); err != nil {
                        paymentRows.Close()
                        log.Printf("[CUSTOMERS] statement payments scan failed: %v", err)
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة كشف الحساب"})
                        return
                }
                entries = append(entries, entry{row: gin.H{
                        "kind":            "payment",
                        "id":              id,
                        "amount_piastres": amount,
                        "note":            note,
                        "created_at":      createdAt,
                }, occurredAt: createdAt})
        }
        paymentRows.Close()
        if err := paymentRows.Err(); err != nil {
                log.Printf("[CUSTOMERS] statement payments rows failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "customers_query_failed", "message": "تعذر قراءة كشف الحساب"})
                return
        }

        // Chronological merge with a running balance (debit = credit sale due,
        // credit = payment received).
        running := money.Piastres(0)
        payload := make([]gin.H, 0, len(entries))
        for i := 0; i < len(entries); i++ {
                for j := i + 1; j < len(entries); j++ {
                        if entries[j].occurredAt.Before(entries[i].occurredAt) {
                                entries[i], entries[j] = entries[j], entries[i]
                        }
                }
                e := entries[i]
                if e.row["kind"] == "credit_sale" {
                        running = running.Add(money.Piastres(e.row["due_amount_piastres"].(money.Piastres)))
                } else {
                        running = running - money.Piastres(e.row["amount_piastres"].(money.Piastres))
                }
                e.row["balance_piastres"] = running
                payload = append(payload, e.row)
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{
                "customer":         gin.H{"id": customerID, "name": customerName, "phone": customerPhone},
                "entries":          payload,
                "balance_piastres": running,
        }})
}

// ---------------------------------------------------------------------------
// Record a payment (تحصيل): POST /pharmacy/customers/:id/payments
// ---------------------------------------------------------------------------

type customerPaymentRequest struct {
        AmountPiastres int64  `json:"amount_piastres"`
        Note           string `json:"note"`
}

func (h *Handler) CreatePharmacyCustomerPayment(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.PharmacyID == "" || principal.ID == "" {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_mutation_account_required", "message": "حساب مدير أو موظف صيدلية مطلوب"})
                return
        }
        customerID := strings.TrimSpace(c.Param("id"))
        if !isUUID(customerID) {
                c.JSON(http.StatusNotFound, gin.H{"error": "customer_not_found", "message": "العميل غير موجود"})
                return
        }
        var request customerPaymentRequest
        if err := c.ShouldBindJSON(&request); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_payment", "message": "بيانات الدفعة غير صحيحة"})
                return
        }
        note := strings.TrimSpace(request.Note)
        if len(note) > maxPaymentNoteLen {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_payment", "message": "ملاحظة الدفعة طويلة جداً"})
                return
        }
        if request.AmountPiastres <= 0 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_payment", "message": "قيمة الدفعة يجب أن تكون أكبر من صفر"})
                return
        }
        employeeID, companyUserID := actorIDs(principal)

        tx, err := h.db.Begin(c.Request.Context())
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_failed", "message": "تعذر تسجيل الدفعة"})
                return
        }
        defer func() { _ = tx.Rollback(c.Request.Context()) }()
        if _, err := tx.Exec(c.Request.Context(), `
                SELECT set_config('app.current_pharmacy_id', $1, true),
                       set_config('app.current_user_id', $2, true)
        `, principal.PharmacyID, principal.ID); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_failed", "message": "تعذر تسجيل الدفعة"})
                return
        }

        // Lock the customer row so concurrent payments serialize cleanly.
        var customerName string
        err = tx.QueryRow(c.Request.Context(), `
                SELECT name::text FROM customers
                WHERE id = $1::uuid AND pharmacy_id = $2
                FOR UPDATE
        `, customerID, principal.PharmacyID).Scan(&customerName)
        if errors.Is(err, pgx.ErrNoRows) {
                c.JSON(http.StatusNotFound, gin.H{"error": "customer_not_found", "message": "العميل غير موجود"})
                return
        }
        if err != nil {
                log.Printf("[CUSTOMERS] payment customer lock failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_failed", "message": "تعذر تسجيل الدفعة"})
                return
        }

        var paymentID string
        var createdAt time.Time
        if err := tx.QueryRow(c.Request.Context(), `
                INSERT INTO customer_payments (pharmacy_id, customer_id, amount, note, employee_id, company_user_id)
                VALUES ($1, $2, $3, NULLIF($4, ''), NULLIF($5, '')::uuid, NULLIF($6, '')::uuid)
                RETURNING id::text, created_at
        `, principal.PharmacyID, customerID, request.AmountPiastres, note, employeeID, companyUserID).
                Scan(&paymentID, &createdAt); err != nil {
                log.Printf("[CUSTOMERS] payment insert failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_failed", "message": "تعذر تسجيل الدفعة"})
                return
        }

        balance, err := customerBalance(c, tx, principal.PharmacyID, customerID)
        if err != nil {
                log.Printf("[CUSTOMERS] payment balance failed: %v", err)
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_failed", "message": "تعذر حساب الرصيد"})
                return
        }
        if err := tx.Commit(c.Request.Context()); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "payment_failed", "message": "تعذر تسجيل الدفعة"})
                return
        }
        c.JSON(http.StatusCreated, gin.H{"data": gin.H{
                "payment_id":       paymentID,
                "balance_piastres": balance,
        }})
}

// customerBalance derives the live balance on the open transaction:
// Σ(credit invoice dues) − Σ(payments).
func customerBalance(ctx context.Context, tx pgx.Tx, pharmacyID, customerID string) (money.Piastres, error) {
        var credit, paid money.Piastres
        err := tx.QueryRow(ctx, `
                SELECT
                    COALESCE((
                        SELECT SUM(s.total_amount - COALESCE(r.total, 0))::int8
                        FROM sales s
                        LEFT JOIN (
                            SELECT sale_id, SUM(total_amount_piastres) AS total
                            FROM sale_returns
                            GROUP BY sale_id
                        ) r ON r.sale_id = s.id
                        WHERE s.customer_id = $1 AND s.payment_type = 'credit'
                    ), 0),
                    COALESCE((
                        SELECT SUM(p.amount)::int8
                        FROM customer_payments p
                        WHERE p.customer_id = $1
                    ), 0)
                FROM (SELECT 1) one
        `, customerID).Scan(&credit, &paid)
        if err != nil {
                return 0, err
        }
        return credit - paid, nil
}

// ---------------------------------------------------------------------------
// Low-stock alerts: GET /pharmacy/inventory/low-stock
// Active products whose min_stock_level > 0 and total base quantity (across
// batches) dropped to/below that level — the header bell fetches this so the
// pharmacist can reorder in time. Sorted by urgency (closest to zero first).
// ---------------------------------------------------------------------------

func (h *Handler) GetPharmacyLowStock(c *gin.Context) {
	pharmacyID, ok := pharmacyScope(c)
	if !ok {
		return
	}
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT pp.id::text,
		       COALESCE(gp.name::text, ''),
		       COALESCE(gp.strength::text, ''),
		       COALESCE(gp.barcode::text, ''),
		       COALESCE(pp.packaging_type::text, ''),
		       COALESCE(pp.units_per_box::int8, 1),
		       ROUND(COALESCE(SUM(ci.quantity), 0))::int8,
		       pp.min_stock_level::int8
		FROM pharmacy_products pp
		JOIN global_products gp ON gp.id = pp.global_product_id
		LEFT JOIN current_inventory ci ON ci.pharmacy_product_id = pp.id
		WHERE pp.pharmacy_id = $1 AND pp.is_active = true AND pp.min_stock_level > 0
		GROUP BY pp.id, gp.name, gp.strength, gp.barcode, pp.packaging_type, pp.units_per_box, pp.min_stock_level
		HAVING ROUND(COALESCE(SUM(ci.quantity), 0)) <= pp.min_stock_level
		ORDER BY (COALESCE(SUM(ci.quantity), 0)::numeric / GREATEST(pp.min_stock_level, 1)) ASC,
		         gp.name ASC
		LIMIT 50
	`, pharmacyID)
	if err != nil {
		log.Printf("[LOWSTOCK] query failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "low_stock_query_failed", "message": "تعذر قراءة أصناف المخزون المنخفض"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id, name, strength, barcode, packagingType string
		var unitsPerBox, quantity, minStock int64
		if err := rows.Scan(&id, &name, &strength, &barcode, &packagingType, &unitsPerBox, &quantity, &minStock); err != nil {
			log.Printf("[LOWSTOCK] scan failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "low_stock_query_failed", "message": "تعذر قراءة أصناف المخزون المنخفض"})
			return
		}
		items = append(items, gin.H{
			"pharmacy_product_id": id,
			"product_name":        name,
			"strength":            strength,
			"barcode":             barcode,
			"packaging_type":      packagingType,
			"units_per_box":       unitsPerBox,
			"quantity_base":       quantity,
			"min_stock_level":     minStock,
		})
	}
	if err := rows.Err(); err != nil {
		log.Printf("[LOWSTOCK] rows failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "low_stock_query_failed", "message": "تعذر قراءة أصناف المخزون المنخفض"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"items": items, "total": len(items)}})
}
