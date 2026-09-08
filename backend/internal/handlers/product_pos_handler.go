package handlers

import (
	"context"
	"errors"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/pharmacy-os/backend/internal/auth"
)

const (
	packagingWholeOnly = "WHOLE_ONLY"
	packagingBoxStrip  = "BOX_STRIP"
)

type createPharmacyProductRequest struct {
	Name                string   `json:"name"`
	GenericName         string   `json:"generic_name"`
	DosageForm          string   `json:"dosage_form"`
	Strength            string   `json:"strength"`
	Barcode             string   `json:"barcode"`
	PackagingType       string   `json:"packaging_type"`
	UnitsPerBox         int      `json:"units_per_box"`
	CostPrice           float64  `json:"cost_price"`
	SellingPrice        float64  `json:"selling_price"`
	PartialSellingPrice *float64 `json:"partial_selling_price"`
	MinStockLevel       float64  `json:"min_stock_level"`
	InitialBoxes        float64  `json:"initial_boxes"`
	InitialStrips       float64  `json:"initial_strips"`
	BatchNumber         string   `json:"batch_number"`
	ExpiryDate          string   `json:"expiry_date"`
}

type posSaleRequest struct {
	Items []posSaleItemRequest `json:"items"`
}

type posSaleItemRequest struct {
	PharmacyProductID string  `json:"pharmacy_product_id"`
	SaleUnit          string  `json:"sale_unit"`
	Quantity          float64 `json:"quantity"`
}

var errPOSSaleInsufficientStock = errors.New("insufficient stock for POS sale")

func (h *Handler) ListPharmacyProducts(c *gin.Context) {
	pharmacyID, ok := pharmacyScope(c)
	if !ok {
		return
	}

	search := strings.TrimSpace(c.Query("search"))
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT pp.id::text, gp.name, COALESCE(gp.generic_name, ''), COALESCE(gp.barcode, ''),
		       pp.packaging_type, pp.units_per_box, pp.selling_price,
		       COALESCE(pp.partial_selling_price, 0), COALESCE(SUM(ci.quantity), 0)
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
			unitsPerBox                                   int
			sellingPrice, partialPrice, stock             float64
		)
		if err := rows.Scan(&id, &name, &genericName, &barcode, &packagingType, &unitsPerBox, &sellingPrice, &partialPrice, &stock); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "products_query_failed", "message": "تعذر قراءة المنتجات"})
			return
		}
		products = append(products, gin.H{
			"id": id, "name": name, "generic_name": genericName, "barcode": barcode,
			"packaging_type": packagingType, "units_per_box": unitsPerBox,
			"selling_price": sellingPrice, "partial_selling_price": partialPrice, "stock": stock,
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
	if request.Name == "" || request.Barcode == "" ||
		(request.PackagingType != packagingWholeOnly && request.PackagingType != packagingBoxStrip) ||
		request.CostPrice < 0 || request.SellingPrice < 0 || request.MinStockLevel < 0 ||
		request.InitialBoxes < 0 || request.InitialStrips < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_product", "message": "يرجى إدخال اسم المنتج والباركود والأسعار والقيم غير السالبة"})
		return
	}
	if request.PackagingType == packagingWholeOnly {
		request.UnitsPerBox = 1
		if request.InitialStrips != 0 || !isWholeProductNumber(request.InitialBoxes) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_initial_stock", "message": "المنتج الذي يباع كعبوة كاملة لا يقبل كمية شرائط"})
			return
		}
	} else {
		if request.UnitsPerBox < 2 || !isWholeProductNumber(request.InitialBoxes) || !isWholeProductNumber(request.InitialStrips) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_units_per_box", "message": "عدد الشرائط داخل العلبة يجب أن يكون 2 على الأقل"})
			return
		}
		if request.PartialSellingPrice != nil && *request.PartialSellingPrice < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_partial_price", "message": "سعر الشريط يجب ألا يكون سالبًا"})
			return
		}
	}
	if !isFiniteProductNumber(request.CostPrice) || !isFiniteProductNumber(request.SellingPrice) ||
		!isFiniteProductNumber(request.MinStockLevel) || !isFiniteProductNumber(request.InitialBoxes) ||
		!isFiniteProductNumber(request.InitialStrips) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_product_number", "message": "الأرقام المدخلة غير صالحة"})
		return
	}

	baseQuantity := request.InitialBoxes*float64(request.UnitsPerBox) + request.InitialStrips
	baseUnit := "box"
	if request.PackagingType == packagingBoxStrip {
		baseUnit = "strip"
	}
	if baseQuantity > 0 && request.BatchNumber == "" {
		request.BatchNumber = "OPENING-" + time.Now().UTC().Format("20060102150405")
	}
	unitCost := request.CostPrice
	if request.PackagingType == packagingBoxStrip {
		unitCost = request.CostPrice / float64(request.UnitsPerBox)
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
	`, principal.PharmacyID, globalProductID, request.CostPrice, request.SellingPrice,
		request.PartialSellingPrice, request.MinStockLevel, request.PackagingType, request.UnitsPerBox).Scan(&pharmacyProductID)
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
		`, batchID, baseQuantity, baseUnit, unitCost, baseQuantity*unitCost, employeeID, companyUserID); err != nil {
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
		unitsPerBox                                          int
		sellingPrice, partialPrice, stock                    float64
	)
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT pp.id::text, gp.name, COALESCE(gp.generic_name, ''), gp.barcode,
		       pp.packaging_type, pp.units_per_box, pp.selling_price,
		       COALESCE(pp.partial_selling_price, 0), COALESCE(SUM(ci.quantity), 0)
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
		"selling_price": sellingPrice, "partial_selling_price": partialPrice, "stock": stock,
	}})
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

	var saleID string
	if err := tx.QueryRow(c.Request.Context(), `
		INSERT INTO sales (pharmacy_id, branch_id, employee_id, company_user_id)
		VALUES ($1, $2, NULLIF($3, '')::uuid, NULLIF($4, '')::uuid) RETURNING id::text
	`, principal.PharmacyID, branchID, employeeID, companyUserID).Scan(&saleID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر إنشاء الفاتورة"})
		return
	}

	var total float64
	for _, item := range request.Items {
		if item.PharmacyProductID == "" || item.Quantity <= 0 || !isFiniteProductNumber(item.Quantity) ||
			!isWholeProductNumber(item.Quantity) ||
			(item.SaleUnit != "box" && item.SaleUnit != "strip") {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_sale_item", "message": "بيانات أحد أصناف الفاتورة غير صحيحة"})
			return
		}
		itemTotal, saleErr := sellPOSItem(c, tx, principal, branchID, saleID, item)
		if saleErr != nil {
			if errors.Is(saleErr, errPOSSaleInsufficientStock) {
				c.JSON(http.StatusConflict, gin.H{"error": "insufficient_stock", "message": "الكمية المطلوبة غير متاحة في المخزون"})
				return
			}
			if errors.Is(saleErr, errInvalidPOSSaleUnit) {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_sale_unit", "message": "وحدة البيع غير مسموحة لهذا المنتج"})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر تسجيل حركة البيع"})
			return
		}
		total += itemTotal
	}
	if _, err := tx.Exec(c.Request.Context(), `UPDATE sales SET total_amount = $2 WHERE id = $1`, saleID, total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر حفظ إجمالي الفاتورة"})
		return
	}
	if err := tx.Commit(c.Request.Context()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "sale_failed", "message": "تعذر تأكيد الفاتورة"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"data": gin.H{"sale_id": saleID, "total_amount": total}})
}

var errInvalidPOSSaleUnit = errors.New("invalid POS sale unit")

func sellPOSItem(c *gin.Context, tx interface {
	QueryRow(context.Context, string, ...interface{}) pgx.Row
	Query(context.Context, string, ...interface{}) (pgx.Rows, error)
	Exec(context.Context, string, ...interface{}) (pgconn.CommandTag, error)
}, principal *auth.Principal, branchID, saleID string, item posSaleItemRequest) (float64, error) {
	var packagingType string
	var unitsPerBox int
	var boxPrice, partialPrice float64
	err := tx.QueryRow(c.Request.Context(), `
		SELECT pp.packaging_type, pp.units_per_box, pp.selling_price,
		       COALESCE(pp.partial_selling_price, pp.selling_price / NULLIF(pp.units_per_box, 0))
		FROM pharmacy_products pp
		WHERE pp.id = $1 AND pp.pharmacy_id = $2 AND pp.is_active = true
	`, item.PharmacyProductID, principal.PharmacyID).Scan(&packagingType, &unitsPerBox, &boxPrice, &partialPrice)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, errInvalidPOSSaleUnit
	}
	if err != nil {
		return 0, err
	}
	if packagingType == packagingWholeOnly && item.SaleUnit != "box" {
		return 0, errInvalidPOSSaleUnit
	}
	if packagingType == packagingBoxStrip && item.SaleUnit == "strip" && unitsPerBox < 2 {
		return 0, errInvalidPOSSaleUnit
	}
	unitFactor := 1.0
	unitPrice := partialPrice
	if item.SaleUnit == "box" {
		unitFactor = float64(unitsPerBox)
		unitPrice = boxPrice
	}
	employeeID, companyUserID := actorIDs(principal)
	requiredBase := item.Quantity * unitFactor
	rows, err := tx.Query(c.Request.Context(), `
		SELECT ib.id::text, ib.quantity::float8, ib.unit::text, ib.cost_per_unit::float8
		FROM inventory_batches ib
		WHERE ib.pharmacy_product_id = $1 AND ib.branch_id = $2
		  AND ib.is_quarantined = false AND ib.quantity > 0
		ORDER BY ib.expiry_date NULLS LAST, ib.received_date, ib.created_at
		FOR UPDATE
	`, item.PharmacyProductID, branchID)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	remaining := requiredBase
	var total float64
	for rows.Next() && remaining > 0.00001 {
		var batchID, baseUnit string
		var available, costPerUnit float64
		if err := rows.Scan(&batchID, &available, &baseUnit, &costPerUnit); err != nil {
			return 0, err
		}
		take := math.Min(available, remaining)
		if take <= 0 {
			continue
		}
		after := available - take
		if _, err := tx.Exec(c.Request.Context(), `
			INSERT INTO sale_items (
				sale_id, pharmacy_product_id, batch_id, sale_unit,
				quantity, base_quantity, unit_price, unit_cost
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		`, saleID, item.PharmacyProductID, batchID, item.SaleUnit, take/unitFactor, take, unitPrice, costPerUnit); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(c.Request.Context(), `
			INSERT INTO stock_movements (
				batch_id, movement_type, quantity, unit, reference_type,
				reference_id, quantity_before, quantity_after, unit_cost,
				total_cost, created_by, created_by_company_user_id, reason
			) VALUES ($1, 'sale'::movement_type, $2, $3::unit_type, 'sale', $4,
			          $5, $6, $7, $8, NULLIF($9, '')::uuid, NULLIF($10, '')::uuid, 'pos_sale')
		`, batchID, -take, baseUnit, saleID, available, after, costPerUnit, -take*costPerUnit, employeeID, companyUserID); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(c.Request.Context(), `UPDATE inventory_batches SET quantity = $2, updated_at = NOW() WHERE id = $1`, batchID, after); err != nil {
			return 0, err
		}
		remaining -= take
		total += (take / unitFactor) * unitPrice
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	if remaining > 0.00001 {
		return 0, errPOSSaleInsufficientStock
	}
	if _, err := tx.Exec(c.Request.Context(), `
		UPDATE pharmacy_products SET last_sold_at = NOW(), updated_at = NOW() WHERE id = $1
	`, item.PharmacyProductID); err != nil {
		return 0, err
	}
	return total, nil
}

func branchForPrincipal(c *gin.Context, tx interface {
	QueryRow(context.Context, string, ...interface{}) pgx.Row
}, principal *auth.Principal) (string, error) {
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

func isFiniteProductNumber(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func isWholeProductNumber(value float64) bool {
	return isFiniteProductNumber(value) && math.Mod(value, 1) == 0
}
