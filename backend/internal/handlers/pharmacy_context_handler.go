package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/pharmacy-os/backend/internal/auth"
)

// GetPharmacyContext returns only the pharmacy, branch, and user data that
// belongs to the authenticated principal. The pharmacy id is never accepted
// from the request.
func (h *Handler) GetPharmacyContext(c *gin.Context) {
	principal, ok := pharmacyPrincipal(c)
	if !ok {
		return
	}

	var pharmacy struct {
		ID           string
		Name         string
		City         string
		Address      string
		Phone        string
		ProductCount int
		BranchID     *string
		BranchName   *string
		BranchCity   *string
	}
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT p.id::text, p.name, COALESCE(p.city, ''), COALESCE(p.address_line1, ''),
		       COALESCE(p.phone, ''), COUNT(DISTINCT pp.id)::int,
		       b.id::text, b.name, b.city
		FROM pharmacies p
		LEFT JOIN pharmacy_products pp
		       ON pp.pharmacy_id = p.id AND pp.is_active = true
		LEFT JOIN branches b
		       ON b.id = p.default_branch_id AND b.is_active = true
		WHERE p.id = $1 AND p.is_active = true
		GROUP BY p.id, p.name, p.city, p.address_line1, p.phone, b.id, b.name, b.city
	`, principal.PharmacyID).Scan(
		&pharmacy.ID, &pharmacy.Name, &pharmacy.City, &pharmacy.Address,
		&pharmacy.Phone, &pharmacy.ProductCount, &pharmacy.BranchID,
		&pharmacy.BranchName, &pharmacy.BranchCity,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "pharmacy_not_found",
			"message": "لم يتم العثور على بيانات الصيدلية الحالية",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"pharmacy": gin.H{
			"id":            pharmacy.ID,
			"name":          pharmacy.Name,
			"city":          pharmacy.City,
			"address":       pharmacy.Address,
			"phone":         pharmacy.Phone,
			"product_count": pharmacy.ProductCount,
		},
		"branch": nullableBranch(pharmacy.BranchID, pharmacy.BranchName, pharmacy.BranchCity),
		"user": gin.H{
			"id":           principal.ID,
			"email":        principal.Email,
			"first_name":   principal.FirstName,
			"last_name":    principal.LastName,
			"display_name": principal.DisplayName,
			"role":         principal.Role,
		},
	})
}

func (h *Handler) ListPharmacyEmployees(c *gin.Context) {
	pharmacyID, ok := pharmacyScope(c)
	if !ok {
		return
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT e.id::text, e.first_name, e.last_name, COALESCE(e.display_name, ''),
		       e.email, COALESCE(e.phone, ''), COALESCE(e.job_title, ''),
		       e.status::text, COALESCE(e.branch_id::text, ''), COALESCE(b.name, ''),
		       e.created_at
		FROM employees e
		LEFT JOIN branches b ON b.id = e.branch_id AND b.pharmacy_id = e.pharmacy_id
		WHERE e.pharmacy_id = $1
		ORDER BY e.is_active DESC, e.first_name, e.last_name
		LIMIT 500
	`, pharmacyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "employees_query_failed", "message": "تعذر تحميل موظفي الصيدلية"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id, firstName, lastName, displayName, email, phone, jobTitle, status, branchID, branchName string
		var createdAt time.Time
		if err := rows.Scan(&id, &firstName, &lastName, &displayName, &email, &phone, &jobTitle, &status, &branchID, &branchName, &createdAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "employees_query_failed", "message": "تعذر قراءة موظفي الصيدلية"})
			return
		}
		items = append(items, gin.H{
			"id": id, "first_name": firstName, "last_name": lastName,
			"display_name": displayName, "email": email, "phone": phone,
			"job_title": jobTitle, "status": status, "branch_id": branchID,
			"branch_name": branchName, "created_at": createdAt.UTC().Format(time.RFC3339),
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "employees_query_failed", "message": "تعذر قراءة موظفي الصيدلية"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": items, "total": len(items)})
}

func (h *Handler) ListPharmacyBranches(c *gin.Context) {
	pharmacyID, ok := pharmacyScope(c)
	if !ok {
		return
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT b.id::text, b.name, COALESCE(b.code, ''), COALESCE(b.phone, ''),
		       COALESCE(b.email, ''), COALESCE(b.address_line1, ''),
		       COALESCE(b.city, ''), b.is_active, COALESCE(e.display_name, e.first_name || ' ' || e.last_name, '')
		FROM branches b
		LEFT JOIN employees e ON e.id = b.manager_employee_id AND e.pharmacy_id = b.pharmacy_id
		WHERE b.pharmacy_id = $1
		ORDER BY b.is_active DESC, b.name
		LIMIT 200
	`, pharmacyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "branches_query_failed", "message": "تعذر تحميل فروع الصيدلية"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id, name, code, phone, email, address, city, manager string
		var isActive bool
		if err := rows.Scan(&id, &name, &code, &phone, &email, &address, &city, &isActive, &manager); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "branches_query_failed", "message": "تعذر قراءة فروع الصيدلية"})
			return
		}
		items = append(items, gin.H{
			"id": id, "name": name, "code": code, "phone": phone,
			"email": email, "address": address, "city": city,
			"is_active": isActive, "manager_name": manager,
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "branches_query_failed", "message": "تعذر قراءة فروع الصيدلية"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": items, "total": len(items)})
}

func (h *Handler) ListPharmacyAttendance(c *gin.Context) {
	pharmacyID, ok := pharmacyScope(c)
	if !ok {
		return
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT ar.id::text, ar.employee_id::text, COALESCE(e.display_name, e.first_name || ' ' || e.last_name),
		       ar.branch_id::text, COALESCE(b.name, ''), ar.clock_in, ar.clock_out,
		       ar.total_minutes, ar.status::text
		FROM attendance_records ar
		JOIN employees e ON e.id = ar.employee_id AND e.pharmacy_id = ar.pharmacy_id
		LEFT JOIN branches b ON b.id = ar.branch_id AND b.pharmacy_id = ar.pharmacy_id
		WHERE ar.pharmacy_id = $1
		ORDER BY ar.clock_in DESC
		LIMIT 500
	`, pharmacyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "attendance_query_failed", "message": "تعذر تحميل سجلات الحضور"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id, employeeID, employeeName, branchID, branchName, status string
		var clockIn time.Time
		var clockOut *time.Time
		var totalMinutes *int
		if err := rows.Scan(&id, &employeeID, &employeeName, &branchID, &branchName, &clockIn, &clockOut, &totalMinutes, &status); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "attendance_query_failed", "message": "تعذر قراءة سجلات الحضور"})
			return
		}
		item := gin.H{
			"id": id, "employee_id": employeeID, "employee_name": employeeName,
			"branch_id": branchID, "branch_name": branchName,
			"clock_in": clockIn.UTC().Format(time.RFC3339), "status": status,
		}
		if clockOut != nil {
			item["clock_out"] = clockOut.UTC().Format(time.RFC3339)
		}
		if totalMinutes != nil {
			item["total_minutes"] = *totalMinutes
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "attendance_query_failed", "message": "تعذر قراءة سجلات الحضور"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": items, "total": len(items)})
}

func pharmacyPrincipal(c *gin.Context) (*auth.Principal, bool) {
	principal, ok := auth.PrincipalFromContext(c)
	if !ok || (principal.Type != auth.EmployeePrincipal && principal.Type != auth.CompanyUserPrincipal) {
		c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_account_required", "message": "حساب صيدلية مطلوب"})
		return nil, false
	}
	if principal.PharmacyID == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_not_assigned", "message": "لا توجد صيدلية مرتبطة بهذا الحساب"})
		return nil, false
	}
	return principal, true
}

func nullableBranch(id, name, city *string) gin.H {
	if id == nil {
		return nil
	}
	return gin.H{"id": *id, "name": valueOrEmpty(name), "city": valueOrEmpty(city)}
}

func valueOrEmpty(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
