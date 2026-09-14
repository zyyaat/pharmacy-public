// Package handlers contains HTTP handlers for the API
package handlers

import (
        "github.com/gin-gonic/gin"
        "github.com/jackc/pgx/v5/pgxpool"
        "github.com/pharmacy-os/backend/internal/auth"
        "github.com/pharmacy-os/backend/internal/config"
        appmiddleware "github.com/pharmacy-os/backend/internal/middleware"
        "github.com/pharmacy-os/backend/internal/repository"
        "github.com/pharmacy-os/backend/internal/subscription"
        "os"
)

// Handler holds all dependencies for HTTP handlers
type Handler struct {
        config  *config.Config
        db      *pgxpool.Pool
        auth    *auth.Handler
        company *CompanyHandler
        subs    *subscription.Service
}

// New creates a new Handler instance
func New(cfg *config.Config, db ...*pgxpool.Pool) *Handler {
        h := &Handler{config: cfg}
        if len(db) > 0 && db[0] != nil {
                h.db = db[0]
                // SaaS plan enforcement (Task 90): one process-wide service
                // backs both the pharmacy and company permission gates.
                h.subs = subscription.NewService(db[0])
                subscription.SetDefault(h.subs)
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
                // SaaS plans management (Task 90): fully dynamic plans +
                // subscription operations + manual payments. All writes are
                // CSRF-guarded like the rest of the platform mutations.
                platformAdmin.GET("/plans", h.ListPlatformPlans)
                platformAdmin.POST("/plans", auth.CSRF(auth.PlatformRealm), h.CreatePlatformPlan)
                platformAdmin.GET("/plans/:id", h.GetPlatformPlan)
                platformAdmin.PUT("/plans/:id", auth.CSRF(auth.PlatformRealm), h.UpdatePlatformPlan)
                platformAdmin.PATCH("/plans/:id/status", auth.CSRF(auth.PlatformRealm), h.UpdatePlatformPlanStatus)
                platformAdmin.DELETE("/plans/:id", auth.CSRF(auth.PlatformRealm), h.DeletePlatformPlan)
                platformAdmin.GET("/features", h.ListPlatformFeatures)
                platformAdmin.GET("/subscriptions", h.ListPlatformSubscriptions)
                platformAdmin.GET("/subscriptions/overview", h.SubscriptionsOverview)
                platformAdmin.POST("/subscriptions", auth.CSRF(auth.PlatformRealm), h.CreatePlatformSubscription)
                platformAdmin.PATCH("/subscriptions/:id", auth.CSRF(auth.PlatformRealm), h.UpdatePlatformSubscription)
                platformAdmin.GET("/payments", h.ListPlatformPayments)
                platformAdmin.POST("/payments/manual", auth.CSRF(auth.PlatformRealm), h.CreateManualPayment)
                platformAdmin.POST("/payments/:id/refund", auth.CSRF(auth.PlatformRealm), h.RefundPlatformPayment)
                // Task 15 — per-company account page: profile + per-company
                // entitlement overrides (plan baseline + per-account merge)
                // + the account's own audit log. Company-scoped routes are
                // NESTED under /companies/:id/* so the wildcard-free path
                // keeps /payments/paymob-diagnostics resolvable.
                platformAdmin.GET("/companies/:id", h.GetPlatformCompany)
                platformAdmin.GET("/companies/:id/entitlements", h.ListCompanyEntitlements)
                platformAdmin.POST("/companies/:id/entitlements", auth.CSRF(auth.PlatformRealm), h.UpsertCompanyEntitlement)
                platformAdmin.DELETE("/companies/:id/entitlements/:eid", auth.CSRF(auth.PlatformRealm), h.DeleteCompanyEntitlement)
                platformAdmin.GET("/companies/:id/logs", h.ListCompanyLogs)
                // Task 90 prod diagnostics — super-admin self-service for the
                // intention 404 investigation: echoes the exact Paymob config
                // and (with PAYMOB_DIAG_API_KEY) lists the integration IDs
                // that really exist on the account. Read-only GET.
                platformAdmin.GET("/payments/paymob-diagnostics", h.PaymobDiagnostics)
                // Central product libraries («مكتبات المنتجات») — the
                // platform control room for the shared catalog: named,
                // country-targeted, versioned libraries with official prices
                // per entry + Excel bulk import (price bulletins). Every
                // write is transactional + audited to platform_audit_logs.
                // Pharmacy-side import/sync ships in the next api level.
                platformAdmin.GET("/libraries", h.ListPlatformLibraries)
                platformAdmin.POST("/libraries", auth.CSRF(auth.PlatformRealm), h.CreatePlatformLibrary)
                platformAdmin.GET("/libraries/:id", h.GetPlatformLibrary)
                platformAdmin.PUT("/libraries/:id", auth.CSRF(auth.PlatformRealm), h.UpdatePlatformLibrary)
                platformAdmin.DELETE("/libraries/:id", auth.CSRF(auth.PlatformRealm), h.DeletePlatformLibrary)
                platformAdmin.POST("/libraries/:id/publish", auth.CSRF(auth.PlatformRealm), h.PublishPlatformLibrary)
                platformAdmin.GET("/libraries/:id/changes", h.ListPlatformLibraryChanges)
                platformAdmin.GET("/libraries/:id/products", h.ListPlatformLibraryProducts)
                platformAdmin.POST("/libraries/:id/products", auth.CSRF(auth.PlatformRealm), h.AddPlatformLibraryProduct)
                platformAdmin.PUT("/libraries/:id/products/:pid", auth.CSRF(auth.PlatformRealm), h.UpdatePlatformLibraryProduct)
                platformAdmin.DELETE("/libraries/:id/products/:pid", auth.CSRF(auth.PlatformRealm), h.RemovePlatformLibraryProduct)
                platformAdmin.POST("/libraries/:id/import/preview", auth.CSRF(auth.PlatformRealm), h.PreviewPlatformLibraryImport)
                platformAdmin.POST("/libraries/:id/import/execute", auth.CSRF(auth.PlatformRealm), h.ExecutePlatformLibraryImport)
                platformAdmin.GET("/catalog/products", h.ListPlatformCatalogProducts)
                platformAdmin.PUT("/catalog/products/:id", auth.CSRF(auth.PlatformRealm), h.UpdatePlatformCatalogProduct)

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
                // Public Paymob webhook (Phase G): no session auth — the proof
                // is the HMAC-SHA512 signature + optional URL token. Registered
                // in the Paymob dashboard as
                // https://<backend-host>/api/v1/payments/webhook/paymob?token=…
                v1.POST("/payments/webhook/paymob", h.PaymobWebhook)
                // Public XPay webhook (Phase X — the replacement gateway): no
                // session auth — the proof is the HMAC-SHA256 XPay-Signature
                // over the raw body + optional URL token. Registered in the
                // XPay dashboard as
                // https://<backend-host>/api/v1/payments/webhook/xpay?token=…
                // Paymob's webhook stays mounted: pending paymob payments keep
                // resolving through their own provider even after the switch.
                v1.POST("/payments/webhook/xpay", h.XPayWebhook)
                // SaaS subscription surface (Task 90): these two are part of
                // the lockout allow-list — an expired/suspended company must
                // always be able to read its own status and the public plans
                // so it can recover. No status gate here, by design.
                pharmacy.GET("/subscription", h.GetPharmacySubscription)
                pharmacy.GET("/plans", h.ListPublicPlans)
                // Phase G — online checkout (EMBEDDED Unified Checkout):
                // deliberately NOT behind the plan permission/status gates —
                // an expired or suspended company must be able to pay to
                // recover, which is the entire point of the recovery flow.
                // Mutation principal + CSRF + server-side company scope still
                // apply. The card form renders INSIDE the app modal; the
                // webhook is the only activation path.
                pharmacy.POST("/subscription/checkout", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), h.CreatePharmacyCheckout)
                pharmacy.GET("/subscription/payments/:id", h.GetPharmacyPaymentStatus)
                // Self-service billing (global best practice): cancel at period
                // end + resume + the company's own payment history. Behind the
                // billing permission EVERY plan grants (a company must always
                // control its own billing) + mutation principal + CSRF on
                // writes. Cancelling is a FLAG, not a kill switch: paid access
                // continues to the end of the period, then normal expiry.
                pharmacy.POST("/subscription/cancel", perm("settings.billing"), auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), h.CancelPharmacySubscription)
                pharmacy.POST("/subscription/resume", perm("settings.billing"), auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), h.ResumePharmacySubscription)
                pharmacy.GET("/subscription/payments", perm("settings.billing"), h.ListPharmacyPayments)
                // Delta sync (offline-first smart synchronization): one cheap
                // round-trip returns only what changed since the caller's
                // cursor + tombstoned deletions, in row shapes identical to
                // the list endpoints (sync_rows.go). Sections self-filter by
                // the same permission keys as their list endpoints, so no
                // route-level permission guard is needed — exactly like
                // /context and /settings.
                pharmacy.GET("/sync", h.GetPharmacySync)
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
                // Internal barcode generation (barcode system v1): a single
                // product gets a barcode from its form, the settings batch
                // panel fills many at once. Both write under the same product
                // management permission and generate server-side only.
                pharmacy.POST("/products/:id/barcode/generate", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.manage_products"), h.GenerateProductBarcode)
                pharmacy.POST("/barcodes/bulk-generate", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.manage_products"), h.BulkGenerateProductBarcodes)
                // استيراد المنتجات من ملف جداول (ترحيل البرامج القديمة)
                pharmacy.GET("/imports/products/template", perm("inventory.import"), h.ProductImportTemplate)
                pharmacy.POST("/imports/products/preview", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.import"), h.PreviewProductImport)
                pharmacy.POST("/imports/products/execute", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.import"), h.ExecuteProductImport)
                // مكتبات المنتجات المركزية (المرحلة 2): المكتبات المرئية
                // للصيدلية حسب البلد + الاستيراد الذكي بالبوابات الثلاث
                // (اختيار ← كشف تكرار ← سقف الخطة) + سحب التحديثات بعد النشر.
                // القاعدة الحمراء: المخزون والتكلفة لا يُمسّان أبدًا.
                pharmacy.GET("/libraries", perm("inventory.view"), h.ListPharmacyLibraries)
                pharmacy.GET("/libraries/:id", perm("inventory.view"), h.GetPharmacyLibrary)
                pharmacy.GET("/libraries/:id/products", perm("inventory.view"), h.ListPharmacyLibraryProducts)
                pharmacy.GET("/libraries/:id/diff", perm("inventory.view"), h.GetPharmacyLibraryDiff)
                pharmacy.POST("/libraries/:id/import/preview", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.import"), h.PreviewPharmacyLibraryImport)
                pharmacy.POST("/libraries/:id/import/execute", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.import"), h.ExecutePharmacyLibraryImport)
                pharmacy.POST("/libraries/:id/sync", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("inventory.import"), h.SyncPharmacyLibrary)
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
                // Label templates (barcode system v1): reading is open to every
                // pharmacy principal (the print action needs it); template
                // management is gated by the dedicated settings.labels
                // permission (migration 23) like every mutating endpoint.
                pharmacy.GET("/settings/labels", h.GetLabelSettings)
                pharmacy.PUT("/settings/labels", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), perm("settings.labels"), h.UpdateLabelSettings)

                // Task 57 — إعداد الصيدلية الذي يفتح مباشرة بعد التحقق من البريد:
                // القراءة لأي جلسة صيدلية صالحة، والكتابة بنفس حرس الطفرات + CSRF
                // كباقي نقاط النهاية المكتوبة. لا صلاحية مفصّلة هنا لأن المالك
                // الجديد يجب أن يمرّ من هذه الصفحة قبل أي إعداد آخر.
                pharmacy.GET("/onboarding", h.GetPharmacyOnboarding)
                // The onboarding write has no single permission key, but it
                // must still respect the subscription lockout (expired/
                // suspended companies are gated by status only).
                pharmacy.PUT("/onboarding", auth.RequirePharmacyMutationPrincipal(), auth.CSRF(auth.PharmacyRealm), h.guardPlanStatus(h.UpdatePharmacyOnboarding))
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
// 59 — delta sync: migration 25 (sales/customers updated_at + triggers,
// sync_tombstones) + GET /pharmacy/sync for the mobile offline cache.
// 60 — SaaS plans & subscriptions: migration 26 (plans/features/limits/
// subscriptions/payments), plan gate inside both permission middlewares,
// limit enforcement at creation endpoints, platform-admin plan/subscription
// management, GET /pharmacy/subscription + /pharmacy/plans.
// 61 — Paymob embedded checkout (Phase G): POST /pharmacy/subscription/checkout
// (intention server-side, client_secret + embed URL for the in-app iframe),
// GET /pharmacy/subscription/payments/:id polling, HMAC-SHA512-verified
// POST /payments/webhook/paymob as the only online activation path, shared
// applySucceededPaymentTx transition for manual + webhook payments.
// 62 — checkout now sends notification_url (our webhook URL + token) on
// every intention so the callback is code-driven, not dashboard-dependent;
// PAYMOB_SECRET_KEY is the canonical secret env name (falls back to the
// legacy PAYMOB_API_KEY).
// 63 — Paymob intention wire contract fixed against the live API: endpoint
// is POST {base}/v1/intention/ (integration ID inside the body as
// payment_methods, never in the URL path) and "amount" is integer
// piastres/cents as-is (the previous major-unit division undercharged by
// 100x); billing country now 3-letter ISO (EGY); locked by
// TestCreateIntentionWireContract.
// 64 — intention resilience: Paymob rejects the WHOLE intention with 404
// "Integration ID does not exist" when ANY payment_methods entry is bad,
// so a stale optional wallet ID no longer blocks card payments — on 404
// with multiple channels the client retries once with the card channel
// alone; HMAC concatenation locked to Paymob's official worked example
// (TestHMACConcatenationMatchesPaymobDocsExample).
// 65 — super-admin diagnostics: GET /platform-admin/payments/paymob-
// diagnostics echoes the exact Paymob config in use (base URL, masked
// keys, literal integration IDs) and — when PAYMOB_DIAG_API_KEY is set —
// probes the legacy API (auth/tokens → integrations list) to enumerate the
// integration IDs that really exist on the account; intention failures now
// log the exact base_url + payment_methods sent, making a dashboard
// mismatch provable from the server log alone.
// 66 — webhook HMAC fix: Paymob delivers the HMAC as a QUERY PARAMETER on
// the callback URL (docs + every official sample); the handler read
// obj["hmac"] from the body (always absent) so EVERY genuine webhook was
// rejected. Now read from the query first (body kept as fallback) +
// forensic log (hmac source/length + exact concatenated string, no
// secrets) on any future failure + HMAC secret fingerprint in the
// paymob-diagnostics response so a Test/Live secret mismatch is visible.
// 67 — subscriptions best-practice pass: 7-day post-expiry GRACE (access
// continues with renewal urgency instead of instant lockout), tenant
// self-service cancel-at-period-end/resume + payment history, admin
// payments ledger + billing overview (MRR/expiring-7d) + refunds with
// optional period shortening, trial-aware extend (extend no longer
// silently converts trials to paid), reactivate always restores access
// (fresh 30-day window when the period end is past), Stripe-style
// idempotency keys on manual payments (migration 27).
// 68 — plan pricing gate: a public+active plan must carry at least one
// positive price (Stripe-model) — closes the "0 EGP" dead-end checkout
// (plan editor no longer accepts unpriced public plans; pharmacy UI renders
// them as contact-support instead of a doomed subscribe button).
// 73 — plan seed repair: migration 26 seeded free/starter plan_permissions
// by joining plan_features BEFORE plan_features was populated, so those
// plans held only the 12-key core set — a company on «البداية» showed an
// ACTIVE subscription while every module API answered plan_permission_denied.
// Migration 28 repairs the data (idempotent, strictly additive), migration
// 27 is wired into the chain retroactively (payments.idempotency_key was
// authored but never applied — manual payments would 42703), and a startup
// consistency guard logs any plan whose features lack their permissions.
// 74 — per-company account page + «التحكم الكامل» (professional SaaS
// pattern): migration 29 adds company_entitlements — per-account
// feature/permission/limit overrides merged ON TOP of the plan baseline
// (resolution: override → plan) inside loadSets, so the permission gate,
// the limit gate and the pharmacy sidebar all see ONE merged source of
// truth; overrides are self-reversing via expires_at and audited. New
// endpoints: GET /platform-admin/companies/:id (+ /entitlements CRUD +
// /logs). Migration 30 adds platform_audit_logs and fixes the silent loss
// of ALL platform billing audit rows: the tenant writeAuditLog requires a
// pharmacy scope a platform principal does not have, so every plan/-
// subscription/payment audit write used to fail under `_ =`.
// 75 — central product libraries («مكتبات المنتجات»): migration 31 adds
// product_libraries (named, country-targeted, versioned, publishable) +
// library_products (the OFFICIAL regulated price lives on the library
// entry, not the global product — one drug, different official prices per
// country/currency) + library_changes (append-only log powering the
// pharmacy «الفرق منذ آخر مزامنة» diff) + pharmacy_library_syncs
// (per-pharmacy last-synced pointer), and global_products gains
// is_verified + source provenance. Platform-admin endpoints under
// /platform-admin/libraries (+ /products sub-tree) and
// /platform-admin/catalog/products: full CRUD, version publishing, Excel
// bulk import (thousands of products, preview→execute like the pharmacy
// import), every write audited to platform_audit_logs. Pharmacy-side
// import/sync ships in the next api level.
// 76 — pharmacy-side library import & sync (product libraries Phase 2):
// GET /pharmacy/libraries (+ /:id, /:id/products, /:id/diff) list the
// libraries visible to this pharmacy (published + country match/universal)
// with per-library sync state («not_imported | up_to_date |
// update_available» + pending change counts). POST /:id/import/preview →
// /import/execute run the three approved gates: selection, dedup against
// the pharmacy's own products (exact barcode → suggest link; pg_trgm name
// similarity ≥ 0.55 surfaces suspects with side-by-side matches, ≥ 0.72
// auto-links during sync), and the plan product limit as a soft gate
// (skipped items flagged plan_limit — never a silent failure). POST
// /:id/sync pulls only the delta since the pharmacy's last synced version.
// Red lines enforced server-side: inventory batches and stock movements are
// never touched, cost_price is never written, selling_price follows the
// official library price, «removed» library entries are informational only
// — imported products stay owned by the pharmacy. Tenant audit rows
// (libraries.import / libraries.sync) via writeAuditLog.
// 77 — XPay replaces Paymob as the active online gateway (Phase X):
// config-driven provider priority (XPAY_SECRET_KEY + XPAY_PUBLISHABLE_KEY +
// XPAY_WEBHOOK_SECRET ⇒ xpay, else the Phase G paymob subset, else manual
// only). POST /checkout/sessions (api.xpay.app) with Idempotency-Key =
// payments.id and metadata.payment_id anchor; web gets the inline drop-in
// (client_secret + pk), mobile/legacy get the hosted session URL on
// embed_url via ui_mode. POST /payments/webhook/xpay: HMAC-SHA256
// XPay-Signature (t,v1 over the raw body, 300s replay window) + optional
// URL token; fulfil ONLY on paymentStatus=paid from checkout.session.completed
// or async_payment_succeeded; event.id dedup; amount tamper check; expired
// / async_payment_failed flip only pending rows. Paymob webhook stays
// mounted — in-flight paymob payments keep resolving. paymob-diagnostics
// now reports active_gateway + the xpay config subset.
const APILevel = 77

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
