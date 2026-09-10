// Package main is the entry point for Pharmacy OS backend
package main

import (
	"context"
	"log"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/pharmacy-os/backend/internal/auth"
	"github.com/pharmacy-os/backend/internal/config"
	"github.com/pharmacy-os/backend/internal/database"
	"github.com/pharmacy-os/backend/internal/handlers"
)

func main() {
	// Load configuration
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		log.Fatalf("Invalid configuration: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	poolConfig, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to parse database configuration: %v", err)
	}
	// Supabase's transaction pooler does not keep prepared statements between
	// connections. Simple query execution works with both pooled and direct
	// PostgreSQL URLs, so use it consistently across hosting providers.
	poolConfig.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeExec
	db, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		log.Fatalf("Failed to initialize database pool: %v", err)
	}
	defer db.Close()
	if err := db.Ping(ctx); err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Apply database migrations before anything else touches the schema.
	// The SQL files are embedded in the binary (backend/migrations), so a
	// single self-contained deployment can bootstrap a fresh database on
	// any hosting provider. Safe to run on every startup.
	migrationCtx, cancelMigrations := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancelMigrations()
	if err := database.RunMigrations(migrationCtx, db); err != nil {
		log.Fatalf("Failed to run database migrations: %v", err)
	}

	// Task 53: self-heal the pharmacy email from its registration source
	// (accounts.contact_email) on every startup. Old edit flows wiped
	// pharmacies.email, hiding the email the owner entered at registration
	// from the branch card and the edit form. Idempotent; see
	// database.HealPharmacyRegistrationEmail for the full story.
	if err := database.HealPharmacyRegistrationEmail(migrationCtx, db); err != nil {
		log.Printf("Warning: pharmacy email self-heal skipped: %v", err)
	}

	// Bootstrap whenever super-admin credentials are configured: mandatory
	// in production, honored in any environment so test harnesses can
	// exercise the platform realm without faking APP_ENV=production
	// (which would force Secure cookies over plain HTTP).
	if cfg.IsProduction() || cfg.BootstrapSuperAdminEmail != "" {
		// The shared startup context may already be spent after a long cold
		// migration run against a fresh database, so the super admin bootstrap
		// gets its own time budget instead of reusing the ping context.
		bootstrapCtx, cancelBootstrap := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancelBootstrap()
		bootstrap := auth.NewService(db, auth.Config{})
		if err := bootstrap.BootstrapSuperAdmin(
			bootstrapCtx,
			cfg.BootstrapSuperAdminEmail,
			cfg.BootstrapSuperAdminPassword,
			cfg.BootstrapSuperAdminFirstName,
			cfg.BootstrapSuperAdminLastName,
			cfg.BootstrapSuperAdminCompany,
		); err != nil {
			log.Fatalf("Failed to bootstrap super admin: %v", err)
		}
		log.Printf("Super admin bootstrap completed or was already satisfied")
	}

	// Initialize handlers
	h := handlers.New(cfg, db)

	// Start server
	log.Printf("Starting server on port %s", cfg.Port)
	if err := h.Run(":" + cfg.Port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
