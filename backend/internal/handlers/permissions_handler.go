package handlers

import (
        "fmt"
        "net/http"
        "sort"
        "strings"
        "time"

        "github.com/gin-gonic/gin"
        "github.com/pharmacy-os/backend/internal/auth"
        "golang.org/x/crypto/bcrypt"
)

// Flexible employee permissions (Task 42):
// - permissions catalog grouped by module (Arabic labels from name_ar)
// - role templates (قوالب جاهزة) with their permission keys
// - per-employee permission toggles: GET/PUT /pharmacy/employees/:id/permissions
// - creating a new employee with an explicit permission set
// - enforcement middleware: requirePharmacyPermission(key)
//
// Rollout safety: employees WITHOUT any explicit permission rows keep full
// access exactly as before this feature. Restriction begins only when the
// owner saves an explicit set. Company admins/managers always pass.

// ============================================================================
// Enforcement middleware
// ============================================================================

const permissionAdminKey = "pharmacy.admin"

// requirePharmacyPermission checks the current principal against the flexible
// permission system. Resolution order:
//  1. company_admin / company_manager principals: always allowed (owners).
//  2. employees holding pharmacy.admin: always allowed.
//  3. employees with explicit permission rows: allowed iff the key is granted.
//  4. employees with no rows at all: allowed (legacy full access — keeps
//     existing accounts working until the owner customizes them).
func (h *Handler) requirePharmacyPermission(permissionKey string) gin.HandlerFunc {
        return func(c *gin.Context) {
                principal, ok := auth.PrincipalFromContext(c)
                if !ok || principal.ID == "" {
                        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                                "error": "authentication_required", "message": "Authentication required",
                        })
                        return
                }

                // Owners (company admin/manager) keep full control of their pharmacy.
                if principal.Type == auth.CompanyUserPrincipal &&
                        (principal.Role == "company_admin" || principal.Role == "company_manager") {
                        c.Next()
                        return
                }
                if principal.Type != auth.EmployeePrincipal {
                        c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                                "error": "permission_denied",
                                "message": "لا تملك صلاحية الوصول لهذا القسم",
                                "code": "PERMISSION_DENIED",
                                "required_permission": permissionKey,
                        })
                        return
                }

                // Load the employee's active permission keys (single query, also tells
                // us whether the employee has ANY explicit rows).
                keys, err := h.employeePermissionKeys(c, principal.ID)
                if err != nil {
                        c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
                                "error": "permission_check_failed", "message": "تعذر التحقق من الصلاحيات",
                        })
                        return
                }

                // Legacy employees with zero explicit rows keep full access.
                if len(keys) == 0 {
                        c.Next()
                        return
                }

                for _, key := range keys {
                        if key == permissionKey {
                                c.Next()
                                return
                        }
                }
                // The pharmacy-wide admin key unlocks everything.
                for _, key := range keys {
                        if key == permissionAdminKey {
                                c.Next()
                                return
                        }
                }

                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                        "error":   "permission_denied",
                        "message": "لا تملك صلاحية الوصول لهذا القسم",
                        "code":    "PERMISSION_DENIED",
                        "required_permission": permissionKey,
                })
                return
        }
}

// requirePharmacyOwner restricts a route to pharmacy owners only
// (company_admin / company_manager principals). Used for system-level
// observability endpoints (e.g. the schema-migrations ledger) that the
// frontend exposes to the owner alone — even a pharmacy.admin employee
// must not read infrastructure metadata through the API.
func (h *Handler) requirePharmacyOwner() gin.HandlerFunc {
        return func(c *gin.Context) {
                principal, ok := auth.PrincipalFromContext(c)
                if !ok || principal.ID == "" {
                        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                                "error": "authentication_required", "message": "Authentication required",
                        })
                        return
                }
                if principal.Type == auth.CompanyUserPrincipal &&
                        (principal.Role == "company_admin" || principal.Role == "company_manager") {
                        c.Next()
                        return
                }
                c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
                        "error":   "permission_denied",
                        "message": "هذه الصفحة متاحة لصاحب الصيدلية فقط",
                        "code":    "OWNER_ONLY",
                })
        }
}

// employeePermissionKeys returns the active permission keys for an employee.
func (h *Handler) employeePermissionKeys(c *gin.Context, employeeID string) ([]string, error) {
        rows, err := h.db.Query(c.Request.Context(), `
                SELECT p.key
                FROM employee_permissions ep
                JOIN permissions p ON p.id = ep.permission_id
                WHERE ep.employee_id = $1 AND ep.revoked_at IS NULL
        `, employeeID)
        if err != nil {
                return nil, err
        }
        defer rows.Close()

        keys := make([]string, 0)
        for rows.Next() {
                var key string
                if err := rows.Scan(&key); err != nil {
                        return nil, err
                }
                keys = append(keys, key)
        }
        return keys, rows.Err()
}

// ============================================================================
// Catalog + templates
// ============================================================================

type permissionEntry struct {
        Key      string `json:"key"`
        NameAr   string `json:"name_ar"`
        Category string `json:"category"`
}

type permissionModule struct {
        Module      string            `json:"module"`
        Label       string            `json:"label"`
        Permissions []permissionEntry `json:"permissions"`
}

var moduleLabels = map[string]string{
        "dashboard":  "لوحة التحكم",
        "pos":        "نقطة البيع",
        "sales":      "المبيعات والفواتير",
        "inventory":  "المخزون والأدوية",
        "products":   "المنتجات",
        "customers":  "حسابات العملاء",
        "employees":  "الموظفون",
        "attendance": "الحضور والانصراف",
        "branches":   "الفروع",
        "reports":    "التقارير",
        "settings":   "الإعدادات",
        "pharmacy":   "إدارة الصيدلية",
        "companies":  "الشركات",
        "accounts":   "الحسابات",
        "platform":   "المنصة",
}

// GetPermissionCatalog returns every permission grouped by module with Arabic
// labels. GET /pharmacy/permissions/catalog
func (h *Handler) GetPermissionCatalog(c *gin.Context) {
        rows, err := h.db.Query(c.Request.Context(), `
                SELECT key, COALESCE(NULLIF(name_ar, ''), name), COALESCE(category, ''),
                       module, sort_order
                FROM permissions
                ORDER BY module, sort_order, key
        `)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_query_failed", "message": "تعذر تحميل كتالوج الصلاحيات"})
                return
        }
        defer rows.Close()

        moduleOrder := make([]string, 0)
        moduleMap := make(map[string]*permissionModule)
        for rows.Next() {
                var key, nameAr, category, module string
                var sortOrder int
                if err := rows.Scan(&key, &nameAr, &category, &module, &sortOrder); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_query_failed", "message": "تعذر قراءة كتالوج الصلاحيات"})
                        return
                }
                // Hide platform/company-only permissions from the pharmacy UI.
                if module == "companies" || module == "accounts" || module == "platform" || module == "products" || module == "company_users" {
                        continue
                }
                mod, exists := moduleMap[module]
                if !exists {
                        label := moduleLabels[module]
                        if label == "" {
                                label = module
                        }
                        mod = &permissionModule{Module: module, Label: label, Permissions: make([]permissionEntry, 0)}
                        moduleMap[module] = mod
                        moduleOrder = append(moduleOrder, module)
                }
                mod.Permissions = append(mod.Permissions, permissionEntry{Key: key, NameAr: nameAr, Category: category})
        }
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "catalog_query_failed", "message": "تعذر قراءة كتالوج الصلاحيات"})
                return
        }

        modules := make([]permissionModule, 0, len(moduleOrder))
        for _, name := range moduleOrder {
                modules = append(modules, *moduleMap[name])
        }
        c.JSON(http.StatusOK, gin.H{"data": modules})
}

type roleTemplate struct {
        ID           string   `json:"id"`
        Name         string   `json:"name"`
        DisplayName  string   `json:"display_name"`
        DisplayNameAr string  `json:"display_name_ar"`
        DescriptionAr string  `json:"description_ar"`
        IsSystem     bool     `json:"is_system"`
        Permissions  []string `json:"permissions"`
}

// GetPermissionTemplates returns the ready-made role templates
// (قوالب الصلاحيات الجاهزة). GET /pharmacy/permissions/templates
func (h *Handler) GetPermissionTemplates(c *gin.Context) {
        roleRows, err := h.db.Query(c.Request.Context(), `
                SELECT id::text, name, COALESCE(display_name, ''),
                       COALESCE(display_name_ar, ''), COALESCE(description_ar, ''), is_system
                FROM roles
                WHERE is_active = true
                ORDER BY sort_order, name
        `)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "templates_query_failed", "message": "تعذر تحميل قوالب الصلاحيات"})
                return
        }
        defer roleRows.Close()

        templates := make([]*roleTemplate, 0)
        indexByID := make(map[string]int)
        for roleRows.Next() {
                var tpl roleTemplate
                if err := roleRows.Scan(&tpl.ID, &tpl.Name, &tpl.DisplayName, &tpl.DisplayNameAr, &tpl.DescriptionAr, &tpl.IsSystem); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "templates_query_failed", "message": "تعذر قراءة قوالب الصلاحيات"})
                        return
                }
                tpl.Permissions = make([]string, 0)
                if tpl.DisplayNameAr == "" {
                        tpl.DisplayNameAr = tpl.DisplayName
                }
                indexByID[tpl.ID] = len(templates)
                templates = append(templates, &tpl)
        }
        if err := roleRows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "templates_query_failed", "message": "تعذر قراءة قوالب الصلاحيات"})
                return
        }

        permRows, err := h.db.Query(c.Request.Context(), `
                SELECT r.id::text, p.key
                FROM role_permissions rp
                JOIN roles r ON r.id = rp.role_id
                JOIN permissions p ON p.id = rp.permission_id
                ORDER BY p.module, p.key
        `)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "templates_query_failed", "message": "تعذر تحميل قوالب الصلاحيات"})
                return
        }
        defer permRows.Close()
        for permRows.Next() {
                var roleID, key string
                if err := permRows.Scan(&roleID, &key); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "templates_query_failed", "message": "تعذر قراءة قوالب الصلاحيات"})
                        return
                }
                if idx, exists := indexByID[roleID]; exists {
                        templates[idx].Permissions = append(templates[idx].Permissions, key)
                }
        }
        if err := permRows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "templates_query_failed", "message": "تعذر قراءة قوالب الصلاحيات"})
                return
        }

        c.JSON(http.StatusOK, gin.H{"data": templates})
}

// GetMyPermissions returns the current principal's permission keys so the UI
// can hide sections the principal cannot open.
// GET /pharmacy/permissions/me
func (h *Handler) GetMyPermissions(c *gin.Context) {
        principal, ok := auth.PrincipalFromContext(c)
        if !ok || principal.ID == "" {
                c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication_required", "message": "Authentication required"})
                return
        }

        payload := gin.H{
                "principal_type": principal.Type,
                "role":           principal.Role,
                "permissions":    make([]string, 0),
                "full_access":    false,
        }

        if principal.Type == auth.CompanyUserPrincipal {
                if principal.Role == "company_admin" || principal.Role == "company_manager" {
                        payload["full_access"] = true
                }
                c.JSON(http.StatusOK, payload)
                return
        }

        keys, err := h.employeePermissionKeys(c, principal.ID)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "permissions_query_failed", "message": "تعذر تحميل الصلاحيات"})
                return
        }
        sort.Strings(keys)
        payload["permissions"] = keys
        // Legacy accounts without explicit rows keep full access; pharmacy.admin
        // also unlocks everything in the UI.
        if len(keys) == 0 {
                payload["full_access"] = true
        }
        for _, key := range keys {
                if key == permissionAdminKey {
                        payload["full_access"] = true
                }
        }
        c.JSON(http.StatusOK, payload)
}

// ============================================================================
// Employee permission toggles
// ============================================================================

// GetEmployeePermissions returns the current toggle state of one employee.
// GET /pharmacy/employees/:id/permissions
func (h *Handler) GetEmployeePermissions(c *gin.Context) {
        employeeID := c.Param("id")
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }

        var employeePharmacyID string
        var displayName, email string
        err := h.db.QueryRow(c.Request.Context(), `
                SELECT pharmacy_id::text, COALESCE(display_name, first_name || ' ' || last_name), email
                FROM employees WHERE id = $1
        `, employeeID).Scan(&employeePharmacyID, &displayName, &email)
        if err != nil {
                c.JSON(http.StatusNotFound, gin.H{"error": "employee_not_found", "message": "الموظف غير موجود"})
                return
        }
        if employeePharmacyID != pharmacyID {
                c.JSON(http.StatusForbidden, gin.H{"error": "employee_out_of_scope", "message": "الموظف لا ينتمي لهذه الصيدلية"})
                return
        }

        keys, err := h.employeePermissionKeys(c, employeeID)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "permissions_query_failed", "message": "تعذر تحميل صلاحيات الموظف"})
                return
        }
        sort.Strings(keys)

        c.JSON(http.StatusOK, gin.H{
                "data": gin.H{
                        "employee_id":   employeeID,
                        "display_name":  displayName,
                        "email":         email,
                        "permissions":   keys,
                        "has_explicit":  len(keys) > 0,
                        "full_access":   len(keys) == 0,
                },
        })
}

// UpdateEmployeePermissions replaces the employee's active permission set with
// the provided keys (the toggle state). The change runs in one transaction:
// revoke what disappeared, grant what is new, keep the rest untouched so the
// grant/revoke audit trail stays intact.
// PUT /pharmacy/employees/:id/permissions
func (h *Handler) UpdateEmployeePermissions(c *gin.Context) {
        employeeID := c.Param("id")
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        principal, _ := auth.PrincipalFromContext(c)

        var body struct {
                Permissions []string `json:"permissions"`
        }
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }

        // Validate + dedupe keys against the catalog.
        wanted := make([]string, 0)
        seen := make(map[string]bool)
        for _, key := range body.Permissions {
                key = strings.TrimSpace(key)
                if key == "" || seen[key] {
                        continue
                }
                seen[key] = true
                wanted = append(wanted, key)
        }

        tx, err := h.db.Begin(c.Request.Context())
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "transaction_failed", "message": "تعذر تنفيذ العملية"})
                return
        }
        defer tx.Rollback(c.Request.Context())

        var employeePharmacyID string
        err = tx.QueryRow(c.Request.Context(), `
                SELECT pharmacy_id::text FROM employees WHERE id = $1
        `, employeeID).Scan(&employeePharmacyID)
        if err != nil {
                c.JSON(http.StatusNotFound, gin.H{"error": "employee_not_found", "message": "الموظف غير موجود"})
                return
        }
        if employeePharmacyID != pharmacyID {
                c.JSON(http.StatusForbidden, gin.H{"error": "employee_out_of_scope", "message": "الموظف لا ينتمي لهذه الصيدلية"})
                return
        }

        // Guard: the caller can never lock themselves out. The acting employee
        // must keep pharmacy.admin or employees.manage_permissions.
        if principal != nil && principal.Type == auth.EmployeePrincipal && principal.ID == employeeID {
                hasSelfGuard := false
                for _, key := range wanted {
                        if key == permissionAdminKey || key == "employees.manage_permissions" {
                                hasSelfGuard = true
                        }
                }
                if !hasSelfGuard {
                        c.JSON(http.StatusBadRequest, gin.H{
                                "error":   "self_lockout_blocked",
                                "message": "لا يمكن إزالة صلاحية إدارة الصلاحيات من حسابك الحالي",
                        })
                        return
                }
        }

        // Resolve current active set.
        current := make(map[string]bool)
        rows, err := tx.Query(c.Request.Context(), `
                SELECT p.key
                FROM employee_permissions ep
                JOIN permissions p ON p.id = ep.permission_id
                WHERE ep.employee_id = $1 AND ep.revoked_at IS NULL
        `, employeeID)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "permissions_query_failed", "message": "تعذر قراءة الصلاحيات الحالية"})
                return
        }
        for rows.Next() {
                var key string
                if err := rows.Scan(&key); err != nil {
                        rows.Close()
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "permissions_query_failed", "message": "تعذر قراءة الصلاحيات الحالية"})
                        return
                }
                current[key] = true
        }
        rows.Close()
        if err := rows.Err(); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "permissions_query_failed", "message": "تعذر قراءة الصلاحيات الحالية"})
                return
        }

        wantedSet := make(map[string]bool, len(wanted))
        for _, key := range wanted {
                wantedSet[key] = true
        }

        // Revoke keys that disappeared (soft delete keeps the audit trail).
        for key := range current {
                if wantedSet[key] {
                        continue
                }
                if _, err := tx.Exec(c.Request.Context(), `
                        UPDATE employee_permissions
                        SET revoked_at = NOW(), revoked_by = $2
                        WHERE employee_id = $1 AND permission_id = (SELECT id FROM permissions WHERE key = $3)
                          AND revoked_at IS NULL
                `, employeeID, nullablePrincipalID(principal), key); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "revoke_failed", "message": "تعذر تحديث الصلاحيات"})
                        return
                }
        }

        // Grant keys that appeared (reactivating a previously revoked row keeps
        // history compact and avoids unique-index conflicts).
        for _, key := range wanted {
                if current[key] {
                        continue
                }
                if _, err := tx.Exec(c.Request.Context(), `
                        INSERT INTO employee_permissions (employee_id, permission_id, granted_by, notes)
                        VALUES ($1, (SELECT id FROM permissions WHERE key = $2), $3, 'صلاحيات مرنة — تعديل يدوي')
                        ON CONFLICT (employee_id, permission_id) WHERE revoked_at IS NULL
                        DO NOTHING
                `, employeeID, key, nullablePrincipalID(principal)); err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "grant_failed", "message": "تعذر تحديث الصلاحيات: صلاحية غير معروفة " + key})
                        return
                }
        }

        // permission_version bumps automatically through the trigger, refreshing
        // cached permission decisions for this employee.
        if err := tx.Commit(c.Request.Context()); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "commit_failed", "message": "تعذر حفظ الصلاحيات"})
                return
        }

        keys, err := h.employeePermissionKeys(c, employeeID)
        if err != nil {
                keys = wanted
        }
        sort.Strings(keys)
        c.JSON(http.StatusOK, gin.H{
                "data": gin.H{
                        "employee_id": employeeID,
                        "permissions": keys,
                        "updated_at":  time.Now().UTC().Format(time.RFC3339),
                },
        })
}

// nullablePrincipalID adapts a company principal (no employees row) to the
// nullable granted_by/revoked_by columns.
func nullablePrincipalID(principal *auth.Principal) *string {
        if principal == nil || principal.ID == "" {
                return nil
        }
        // Only employee rows are valid FK targets for granted_by; company users
        // and other principals are recorded as NULL (notes keep the context).
        if principal.Type != auth.EmployeePrincipal {
                return nil
        }
        id := principal.ID
        return &id
}

// ============================================================================
// Create employee (with template/permission set) + activate/deactivate
// ============================================================================

// CreatePharmacyEmployee adds a new staff member with an optional ready-made
// template and an explicit permission set (the toggle state chosen in the UI).
// POST /pharmacy/employees
func (h *Handler) CreatePharmacyEmployee(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        principal, _ := auth.PrincipalFromContext(c)

        var body struct {
                FirstName   string   `json:"first_name"`
                LastName    string   `json:"last_name"`
                Email       string   `json:"email"`
                Password    string   `json:"password"`
                Phone       string   `json:"phone"`
                JobTitle    string   `json:"job_title"`
        Role        string   `json:"role"`
                BranchID    string   `json:"branch_id"`
                TemplateID  string   `json:"template_id"`
                Permissions []string `json:"permissions"`
        }
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }

        body.FirstName = strings.TrimSpace(body.FirstName)
        body.LastName = strings.TrimSpace(body.LastName)
        body.Email = strings.TrimSpace(strings.ToLower(body.Email))
        body.Phone = strings.TrimSpace(body.Phone)
        body.JobTitle = strings.TrimSpace(body.JobTitle)
        body.BranchID = strings.TrimSpace(body.BranchID)
        body.TemplateID = strings.TrimSpace(body.TemplateID)
        body.Role = strings.TrimSpace(body.Role)
        switch body.Role {
        case "":
                body.Role = "pharmacist"
        case "pharmacist", "cashier", "inventory_manager", "accountant", "hr_manager", "pharmacy_admin":
                // allowed staff roles
        default:
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_role", "message": "الوظيفة غير معروفة"})
                return
        }

        if body.FirstName == "" || body.LastName == "" || body.Email == "" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "missing_fields", "message": "الاسم والبريد الإلكتروني مطلوبان"})
                return
        }
        if len(body.Password) < 8 {
                c.JSON(http.StatusBadRequest, gin.H{"error": "weak_password", "message": "كلمة المرور يجب ألا تقل عن 8 أحرف"})
                return
        }

        // Employees log in with their email — it must not collide with the owner's
        // company-user login (login resolution checks company users first).
        var emailClash bool
        if err := h.db.QueryRow(c.Request.Context(), `
                SELECT EXISTS(
                        SELECT 1 FROM company_users cu
                        JOIN accounts a ON a.company_id = cu.company_id AND a.deleted_at IS NULL
                        JOIN pharmacies p ON p.account_id = a.id
                        WHERE p.id = $1 AND LOWER(cu.email) = LOWER($2) AND cu.deleted_at IS NULL
                )
        `, pharmacyID, body.Email).Scan(&emailClash); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "email_check_failed", "message": "تعذر التحقق من البريد الإلكتروني"})
                return
        }
        if emailClash {
                c.JSON(http.StatusConflict, gin.H{"error": "email_taken", "message": "هذا البريد مستخدم بالفعل في حساب الصيدلية"})
                return
        }

        var accountID string
        if err := h.db.QueryRow(c.Request.Context(), `
                SELECT account_id::text FROM pharmacies WHERE id = $1
        `, pharmacyID).Scan(&accountID); err != nil {
                c.JSON(http.StatusForbidden, gin.H{"error": "pharmacy_not_found", "message": "الصيدلية غير موجودة"})
                return
        }

        hash, err := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "hash_failed", "message": "تعذر تجهيز كلمة المرور"})
                return
        }

        tx, err := h.db.Begin(c.Request.Context())
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "transaction_failed", "message": "تعذر تنفيذ العملية"})
                return
        }
        defer tx.Rollback(c.Request.Context())

        // Owner-created staff accounts are immediately login-ready.
        var employeeID string
        var branchArg interface{}
        if body.BranchID != "" {
                branchArg = body.BranchID
        }
        err = tx.QueryRow(c.Request.Context(), `
                INSERT INTO employees (
                        account_id, pharmacy_id, branch_id, email, first_name, last_name,
                        display_name, phone, job_title, role, status,
                        password_hash, email_verified_at
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, NULLIF($8, ''), NULLIF($9, ''), $10, 'active',
                          $11, NOW())
                RETURNING id::text
        `, accountID, pharmacyID, branchArg, body.Email, body.FirstName, body.LastName,
                strings.TrimSpace(body.FirstName+" "+body.LastName), body.Phone, body.JobTitle, body.Role,
                string(hash)).Scan(&employeeID)
        if err != nil {
                if strings.Contains(err.Error(), "employees_unique_email_per_pharmacy") || strings.Contains(err.Error(), "duplicate key") {
                        c.JSON(http.StatusConflict, gin.H{"error": "email_taken", "message": "هذا البريد مستخدم بالفعل لهذه الصيدلية"})
                        return
                }
                c.JSON(http.StatusInternalServerError, gin.H{"error": "employee_insert_failed", "message": "تعذر إضافة الموظف"})
                return
        }

        // Permission set: explicit list wins; otherwise fall back to template.
        keys := make([]string, 0)
        seen := make(map[string]bool)
        for _, key := range body.Permissions {
                key = strings.TrimSpace(key)
                if key != "" && !seen[key] {
                        seen[key] = true
                        keys = append(keys, key)
                }
        }
        if len(keys) == 0 && body.TemplateID != "" {
                tplRows, err := tx.Query(c.Request.Context(), `
                        SELECT p.key
                        FROM role_permissions rp
                        JOIN permissions p ON p.id = rp.permission_id
                        WHERE rp.role_id = $1
                        ORDER BY p.key
                `, body.TemplateID)
                if err != nil {
                        c.JSON(http.StatusInternalServerError, gin.H{"error": "template_query_failed", "message": "تعذر تحميل قالب الصلاحيات"})
                        return
                }
                for tplRows.Next() {
                        var key string
                        if err := tplRows.Scan(&key); err != nil {
                                tplRows.Close()
                                c.JSON(http.StatusInternalServerError, gin.H{"error": "template_query_failed", "message": "تعذر تحميل قالب الصلاحيات"})
                                return
                        }
                        if !seen[key] {
                                seen[key] = true
                                keys = append(keys, key)
                        }
                }
                tplRows.Close()
        }

        grantedBy := nullablePrincipalID(principal)
        for _, key := range keys {
                if _, err := tx.Exec(c.Request.Context(), `
                        INSERT INTO employee_permissions (employee_id, permission_id, granted_by, notes)
                        VALUES ($1, (SELECT id FROM permissions WHERE key = $2), $3, 'صلاحيات أولية عند إضافة الموظف')
                        ON CONFLICT (employee_id, permission_id) WHERE revoked_at IS NULL
                        DO NOTHING
                `, employeeID, key, grantedBy); err != nil {
                        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_permission", "message": "صلاحية غير معروفة: " + key})
                        return
                }
        }

        if err := tx.Commit(c.Request.Context()); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "commit_failed", "message": "تعذر حفظ الموظف"})
                return
        }

        finalKeys, err := h.employeePermissionKeys(c, employeeID)
        if err != nil {
                finalKeys = keys
        }
        sort.Strings(finalKeys)

        c.JSON(http.StatusCreated, gin.H{
                "data": gin.H{
                        "id":          employeeID,
                        "email":       body.Email,
                        "first_name":  body.FirstName,
                        "last_name":   body.LastName,
                        "permissions": finalKeys,
                        "has_explicit": len(finalKeys) > 0,
                },
        })
}

// SetPharmacyEmployeeStatus activates or deactivates a staff account
// (تفعيل/إيقاف الموظف). Deactivation blocks login instantly.
// PATCH /pharmacy/employees/:id/status
func (h *Handler) SetPharmacyEmployeeStatus(c *gin.Context) {
        pharmacyID, ok := pharmacyScope(c)
        if !ok {
                return
        }
        employeeID := c.Param("id")

        var body struct {
                Status string `json:"status"`
        }
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_body", "message": "صيغة الطلب غير صحيحة"})
                return
        }
        status := strings.ToLower(strings.TrimSpace(body.Status))
        if status != "active" && status != "inactive" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_status", "message": "الحالة المسموحة: active أو inactive"})
                return
        }

        principal, _ := auth.PrincipalFromContext(c)
        if principal != nil && principal.Type == auth.EmployeePrincipal && principal.ID == employeeID && status == "inactive" {
                c.JSON(http.StatusBadRequest, gin.H{"error": "self_deactivation_blocked", "message": "لا يمكنك إيقاف حسابك الحالي"})
                return
        }

        tag, err := h.db.Exec(c.Request.Context(), `
                UPDATE employees SET status = $2::employee_status, is_active = ($2 = 'active'),
                updated_at = NOW()
                WHERE id = $1 AND pharmacy_id = $3
        `, employeeID, status, pharmacyID)
        if err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": "status_update_failed", "message": "تعذر تحديث حالة الموظف"})
                return
        }
        if tag.RowsAffected() == 0 {
                c.JSON(http.StatusNotFound, gin.H{"error": "employee_not_found", "message": "الموظف غير موجود"})
                return
        }

        // Deactivated employees lose active sessions immediately.
        if status == "inactive" {
                if _, err := h.db.Exec(c.Request.Context(), `
                        DELETE FROM auth_sessions
                        WHERE principal_type = 'employee' AND principal_id = $1
                `, employeeID); err != nil {
                        // Session cleanup is best-effort; the login check still blocks.
                        fmt.Printf("[PERMISSIONS] session cleanup failed for %s: %v\n", employeeID, err)
                }
        }

        c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": employeeID, "status": status}})
}
