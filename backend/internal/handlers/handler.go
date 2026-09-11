// Package handlers contains HTTP handlers for the API
package handlers

import (
        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5/pgxpool"
        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/config"
        appmiddleware "github.com/pharmacy-os/backend/internal/middleware"
        "github.com/pharmacy-os/backend/internal/repository"
        "os"
)

// Handler holds all dependencies for HTTP handlers
type Handler struct {
        config  *config.Config
        db      *pgxpool.Pool
        auth    *auth.Handler
        company *CompanyHandler
}

// New creates a new Handler instance
func New(cfg *config.Config, db ...*pgxpool.Pool) *Handler {
        h := &Handler{config: cfg}
        if len(db) > 0 && db[0] != nil {
                h.db = db[0]
                h.auth = auth.NewHandler(db[0], auth.Config{
                        AccessTTL:     cfg.AuthAccessTTL,
                        RefreshTTL:    cfg.AuthRefreshTTL,
                        CookieSecure:  cfg.CookieSecure,
                        CookieDomain:  cfg.CookieDomain,
                        BrevoAPIKey:   cfg.BrevoAPIKey,
                        MailFromEmail: cfg.MailFromEmail,
                        MailFromName:  cfg.MailFromName,
                        PublicAppURL:  cfg.PublicAppURL,
                })
                h.company = NewCompanyHandler(
                        repository.NewCompanyRepository(db[0]),
                        repository.NewCompanyUserRepository(db[0]),
                        repository.NewCompanyUserPermissionRepository(db[0]),
                        nil,
                )
        }
        return h
}

// SetupRoutes configures all API routes
func (h *Handler) SetupRoutes(r *gin.Engine) {
        // Allow the configured frontend origins to call the API.
        r.Use(appmiddleware.CORS(h.config.GetCorsOrigins()...))

        // Root health endpoint for deployment startup probes.
        r.GET("/", h.HealthCheck)

        // API v1 group
        v1 := r.Group("/api/v1")

        // Health check (both /health and /api/v1/health for compatibility)
        r.GET("/health", h.HealthCheck)
        v1.GET("/health", h.HealthCheck)

        if h.auth != nil {
                h.auth.RegisterRoutes(v1)

                // Company dashboard data is always scoped by the authenticated
                // company session. The handlers derive the company id from the
                // principal instead of accepting it from the client.
                dashboard := v1.Group("/dashboard")
                dashboard.Use(h.auth.Middleware(auth.PlatformRealm))
                dashboard.Use(appmiddleware.CompanySessionContext())
                dashboard.Use(appmiddleware.CompanyDBPoolContext(h.db))
                dashboard.Use(appmiddleware.RequireCompanyPermission("companies.view"))
                dashboard.GET("/stats", h.GetDashboardStats)
                dashboard.GET("/activity", h.GetRecentActivity)

                // Platform admin routes are global. They have their own explicit
                // super-admin guard and never reuse company-scoped dashboard routes.
                platformAdmin := v1.Group("/platform-admin")
                platformAdmin.Use(h.auth.Middleware(auth.PlatformRealm))
                platformAdmin.Use(requirePlatformSuperAdmin())
                platformAdmin.GET("/stats", h.GetPlatformAdminStats)
                platformAdmin.GET("/settings", h.GetPlatformSettings)
                platformAdmin.PATCH("/settings", auth.CSRF(auth.PlatformRealm), h.UpdatePlatformSettings)
                platformAdmin.GET("/companies", h.ListPlatformCompanies)
                platformAdmin.GET("/users", h.ListPlatformUsers)
                platformAdmin.GET("/accounts", h.ListPlatformAccounts)
                platformAdmin.GET("/permissions", h.ListPlatformPermissions)

                // Pharmacy data is scoped from the authenticated employee/company
                // principal. These endpoints intentionally do not accept a pharmacy
                // id in the URL or query string.
                pharmacy := v1.Group("/pharmacy")
                pharmacy.Use(h.auth.Middleware(auth.PharmacyRealm))
                pharmacy.Use(auth.RequirePharmacyPrincipal())

                // Flexible permission guards (Task 42). Company owners
                // (admin/manager) and legacy employees without explicit
                // permission rows pass through untouched — existing workflows
                // keep working. Only employees with an explicit permission set
                // are restricted to what the owner granted them.
                perm := h.requirePharmacyPermission

                pharmacy.GET("/context", h.GetPharmacyContext)
                pharmacy.GET("/dashboard/stats", perm("dashboard.view"), h.GetPharmacyDashboardStats)
                pharmacy.GET("/dashboard/activity", perm("dashboard.view"), h.GetPharmacyDashboardActivity)
                pharmacy.GET("/inventory", perm("inventory.view"), h.GetPharmacyInventory)
                pharmacy.GET("/inventory/movements", perm("inventory.movements.view"), h.ListPharmacyStockMovements)
                pharmacy.GET("/inventory/low-stock", perm("inventory.view"), h.GetPharmacyLowStock)
                pharmacy.GET("/system/migrations", h.requirePharmacyOwner(), h.GetSystemMigrations)
                pharmacy.GET("/products", perm("inventory.view"), h.ListPharmacyProducts)
                pharmacy.POST("/products", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.manage_products"), h.CreatePharmacyProduct)
                pharmacy.GET("/products/:id", perm("inventory.view"), h.GetPharmacyProduct)
                pharmacy.PUT("/products/:id", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.manage_products"), h.UpdatePharmacyProduct)
                // استيراد المنتجات من ملف جداول (ترحيل البرامج القديمة)
                pharmacy.GET("/imports/products/template", perm("inventory.import"), h.ProductImportTemplate)
                pharmacy.POST("/imports/products/preview", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.import"), h.PreviewProductImport)
                pharmacy.POST("/imports/products/execute", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.import"), h.ExecuteProductImport)
                pharmacy.GET("/pos/products", perm("pos.access"), h.LookupPOSProduct)
                pharmacy.GET("/pos/search", perm("pos.access"), h.SearchPOSProducts)
                pharmacy.POST("/pos/sales", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("pos.access"), h.CreatePOSSale)
                pharmacy.GET("/pos/sales", perm("sales.view"), h.ListPOSSales)
                pharmacy.GET("/customers", perm("customers.view"), h.ListPharmacyCustomers)
                pharmacy.POST("/customers", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("customers.create"), h.CreatePharmacyCustomer)
                pharmacy.GET("/customers/:id/statement", perm("customers.view"), h.GetPharmacyCustomerStatement)
                pharmacy.POST("/customers/:id/payments", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("customers.payments"), h.CreatePharmacyCustomerPayment)
                pharmacy.PUT("/customers/:id", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("customers.update"), h.UpdatePharmacyCustomer)
                pharmacy.GET("/pos/sales/:sale_id", perm("sales.view"), h.GetPOSSale)
                pharmacy.POST("/pos/sales/:sale_id/returns", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("sales.returns"), h.CreatePOSSaleReturn)
                pharmacy.POST("/inventory/:batch_id/adjust", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.adjust"), h.AdjustPharmacyInventory)
                // Reports are read-only aggregates scoped by the session
                // principal — no mutation guard needed.
                pharmacy.GET("/reports/sales", perm("reports.sales"), h.GetPharmacySalesReport)
                pharmacy.GET("/reports/inventory", perm("reports.inventory"), h.GetPharmacyInventoryReport)
                pharmacy.GET("/reports/movements", perm("reports.movements"), h.GetPharmacyMovementsReport)

                // Flexible permission APIs (catalog/templates are open to every
                // pharmacy principal; management APIs require the matching
                // employees.* permissions like every other mutating endpoint).
                pharmacy.GET("/permissions/catalog", h.GetPermissionCatalog)
                pharmacy.GET("/permissions/templates", h.GetPermissionTemplates)
                pharmacy.GET("/permissions/me", h.GetMyPermissions)
                pharmacy.GET("/employees", perm("employees.view"), h.ListPharmacyEmployees)
                pharmacy.POST("/employees", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("employees.create"), h.CreatePharmacyEmployee)
                pharmacy.GET("/employees/:id/permissions", perm("employees.manage_permissions"), h.GetEmployeePermissions)
                pharmacy.PUT("/employees/:id/permissions", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("employees.manage_permissions"), h.UpdateEmployeePermissions)
                pharmacy.PATCH("/employees/:id/status", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("employees.update"), h.SetPharmacyEmployeeStatus)

                // Branches (Task 50): the branches tab is the single place to
                // manage pharmacy locations — read for every principal, write
                // behind the matching mutation guard + CSRF + permission.
                pharmacy.GET("/branches", perm("branches.view"), h.ListPharmacyBranches)
                pharmacy.POST("/branches", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("branches.create"), h.CreatePharmacyBranch)
                pharmacy.PUT("/branches/:id", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("branches.update"), h.UpdatePharmacyBranch)
                pharmacy.DELETE("/branches/:id", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("branches.delete"), h.DeletePharmacyBranch)
                pharmacy.GET("/attendance", perm("attendance.view"), h.ListPharmacyAttendance)
                // Pharmacy settings: receipt/print configuration. Reading is
                // open to every pharmacy principal; writing follows the same
                // mutation guard + CSRF as every other mutating endpoint.
                pharmacy.GET("/settings", h.GetPharmacySettings)
                pharmacy.PUT("/settings", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("settings.general"), h.UpdatePharmacySettings)

                // Task 57 — إعداد الصيدلية الذي يفتح مباشرة بعد التحقق من البريد:
                // القراءة لأي جلسة صيدلية صالحة، والكتابة بنفس حرس الطفرات + CSRF
                // كباقي نقاط النهاية المكتوبة. لا صلاحية مفصّلة هنا لأن المالك
                // الجديد يجب أن يمرّ من هذه الصفحة قبل أي إعداد آخر.
                pharmacy.GET("/onboarding", h.GetPharmacyOnboarding)
                pharmacy.PUT("/onboarding", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), h.UpdatePharmacyOnboarding)
        }
        // Temporary diagnostics for legacy-schema forensics. Only exposed when
        // APP_DEBUG=true; remove APP_DEBUG from the hosting environment in production.
        if os.Getenv("APP_DEBUG") == "true" {
                v1.GET("/debug/schema", h.DebugSchema)
        }

        // Domain routes use the central opaque session created by /auth/login.
        // The legacy company JWT middleware is intentionally not registered.
        if h.company != nil {
                company := v1.Group("/companies")
                company.Use(h.auth.Middleware(auth.PlatformRealm))
                company.Use(appmiddleware.CompanySessionContext())
                company.Use(appmiddleware.CompanyDBPoolContext(h.db))
                company.Use(appmiddleware.RequireCompanyPermission("companies.view"))

                company.GET("", h.company.ListCompanies)
                company.GET("/:id", h.company.GetCompany)
                company.GET("/:id/summary", h.company.GetCompanySummary)
                company.PUT("/:id", appmiddleware.RequireCompanyPermission("companies.update"), h.company.UpdateCompany)
                company.PATCH("/:id/status", appmiddleware.RequireCompanyPermission("companies.update"), h.company.UpdateCompanyStatus)
                company.DELETE("/:id", appmiddleware.RequireCompanyPermission("companies.delete"), h.company.DeleteCompany)
        }
}

// APILevel is bumped with every behavioral backend change so a deployment's
// code state is verifiable from outside without credentials (Task 57: smart
// registration — verifying the email OTP now opens the session immediately
// and the pharmacy onboarding wizard ships with api_level 57; if /health
// reports a lower value, the running backend predates the deploy).
const APILevel = 57

// HealthCheck returns the health status of the API
func (h *Handler) HealthCheck(c *gin.Context) {
        c.JSON(200, gin.H{
                "status":    "healthy",
                "service":   "pharmacy-os-api",
                "api_level": APILevel,
        })
}

// Run starts the HTTP server
func (h *Handler) Run(addr string) error {
        r := gin.Default()
        h.SetupRoutes(r)
        return r.Run(addr)
}
