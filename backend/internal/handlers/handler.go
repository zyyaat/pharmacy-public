// Package handlers contains HTTP handlers for the API
package handlers

import (
	"context"
	"log"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/pharmacy-os/backend/internal/auth"
	"github.com/pharmacy-os/backend/internal/config"
	appmiddleware "github.com/pharmacy-os/backend/internal/middleware"
	"github.com/pharmacy-os/backend/internal/repository"
)

// keyTables are the tables every active migration must have created. The
// health endpoint reports which of them are missing so a broken deployment
// answers the question "did the migrations actually run?" with a single GET.
var keyTables = []string{
	// 01_foundation
	"accounts", "pharmacies", "branches", "employees",
	// 02_products_inventory
	"global_products", "pharmacy_products", "inventory_batches", "stock_movements",
	// 03_permissions_auth
	"permissions", "roles", "employee_permissions",
	// 04_audit_logs
	"audit_logs", "attendance_records",
	// 05_holding_company
	"companies", "company_users", "company_user_permissions",
	// 06_go_auth
	"auth_sessions", "auth_email_tokens",
}

// Handler holds all dependencies for HTTP handlers
type Handler struct {
	config    *config.Config
	db        *pgxpool.Pool
	auth      *auth.Handler
	company   *CompanyHandler
	startedAt time.Time
}

// New creates a new Handler instance
func New(cfg *config.Config, db ...*pgxpool.Pool) *Handler {
	h := &Handler{config: cfg, startedAt: time.Now()}
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
	}

	// Domain routes use the central opaque session created by /auth/login.
	// The legacy company JWT middleware is intentionally not registered.
	if h.company != nil {
		company := v1.Group("/companies")
		company.Use(h.auth.Middleware())
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

// Run starts the HTTP server with the full diagnostic middleware stack:
// correlation IDs, structured request logs, panic recovery with details and
// CORS. gin.New() is used instead of gin.Default() so the custom middleware
// replaces the noisy default logger/recovery pair.
func (h *Handler) Run(addr string) error {
	r := gin.New()
	r.Use(appmiddleware.RequestID())
	r.Use(appmiddleware.InjectDebug(h.config.Debug))
	r.Use(appmiddleware.Logger())
	r.Use(appmiddleware.RecoveryDebug(h.config.Debug))
	h.SetupRoutes(r)
	return r.Run(addr)
}

// HealthCheck returns an in-depth health report used both by deployment
// probes and by the frontend connection diagnostics panel. It always answers
// 200 (so startup probes never flap) but the "status" field distinguishes
// "healthy" from "degraded" and the "database" object carries the exact
// migration/table state.
func (h *Handler) HealthCheck(c *gin.Context) {
	response := gin.H{
		"status":         "healthy",
		"service":        "pharmacy-os-api",
		"time":           time.Now().UTC().Format(time.RFC3339),
		"uptime_seconds": int64(time.Since(h.startedAt).Seconds()),
		"environment":    h.config.Environment,
		"debug":          h.config.Debug,
		"request_id":     appmiddleware.RequestIDFromContext(c),
		"auth": gin.H{
			"cookie_secure": h.config.CookieSecure,
			"cookie_domain": h.config.CookieDomain,
		},
		"cors": gin.H{
			"allowed_origins": h.config.GetCorsOrigins(),
		},
	}

	dbReport, dbOK := h.databaseReport(c.Request.Context())
	response["database"] = dbReport
	if !dbOK {
		response["status"] = "degraded"
	}

	c.JSON(200, response)
}

// databaseReport pings the database and verifies migrations + key tables.
// The boolean return mirrors overall database health.
func (h *Handler) databaseReport(ctx context.Context) (gin.H, bool) {
	report := gin.H{"ok": false}

	if h.db == nil {
		report["error"] = "database pool not initialized"
		return report, false
	}

	pingCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if err := h.db.Ping(pingCtx); err != nil {
		report["error"] = "ping failed: " + err.Error()
		return report, false
	}

	report["ok"] = true
	report["host"] = maskDatabaseHost(h.config.DatabaseURL)

	// Verify the migration ledger and which chain versions are recorded.
	queryCtx, cancelQuery := context.WithTimeout(ctx, 3*time.Second)
	defer cancelQuery()

	var appliedCount int
	err := h.db.QueryRow(queryCtx,
		`SELECT count(*) FROM public.schema_migrations`).Scan(&appliedCount)
	if err != nil {
		report["migrations"] = gin.H{
			"ok":    false,
			"error": "schema_migrations not readable: " + err.Error(),
		}
		return report, false
	}

	versions := []string{}
	rows, err := h.db.Query(queryCtx, `SELECT version FROM public.schema_migrations ORDER BY version`)
	if err == nil {
		for rows.Next() {
			var version string
			if scanErr := rows.Scan(&version); scanErr == nil {
				versions = append(versions, version)
			}
		}
		rows.Close()
	}
	report["migrations"] = gin.H{
		"ok":      true,
		"applied": appliedCount,
		"versions": versions,
	}

	// Verify key tables exist (the direct answer to "were tables created?").
	existing := map[string]bool{}
	tableRows, err := h.db.Query(queryCtx,
		`SELECT c.relname FROM pg_class c
		 JOIN pg_namespace n ON n.oid = c.relnamespace
		 WHERE n.nspname = 'public' AND c.relkind = 'r'`)
	if err != nil {
		report["tables"] = gin.H{"ok": false, "error": err.Error()}
		return report, false
	}
	for tableRows.Next() {
		var name string
		if scanErr := tableRows.Scan(&name); scanErr == nil {
			existing[name] = true
		}
	}
	tableRows.Close()

	missing := []string{}
	for _, table := range keyTables {
		if !existing[table] {
			missing = append(missing, table)
		}
	}
	tableReport := gin.H{"ok": len(missing) == 0, "checked": len(keyTables)}
	if len(missing) > 0 {
		tableReport["missing"] = missing
		tableReport["error"] = "missing tables (migrations incomplete)"
		log.Printf("[HEALTH] missing tables detected: %v", missing)
	}
	report["tables"] = tableReport

	return report, len(missing) == 0
}

// maskDatabaseHost shows only the host portion of DATABASE_URL in reports.
func maskDatabaseHost(databaseURL string) string {
	at := -1
	for i := len(databaseURL) - 1; i >= 0; i-- {
		if databaseURL[i] == '@' {
			at = i
			break
		}
	}
	if at < 0 {
		return "(hidden)"
	}
	rest := databaseURL[at+1:]
	slash := -1
	for i := 0; i < len(rest); i++ {
		if rest[i] == '/' {
			slash = i
			break
		}
	}
	if slash >= 0 {
		rest = rest[:slash]
	}
	return rest
}
