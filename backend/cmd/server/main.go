// Package main is the entry point for Pharmacy OS backend
package main

import (
	"context"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/pharmacy-os/backend/internal/config"
	"github.com/pharmacy-os/backend/internal/database"
	"github.com/pharmacy-os/backend/internal/handlers"
)

func main() {
	// Load configuration
	cfg := config.Load()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	db, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to initialize database pool: %v", err)
	}
	defer db.Close()
	if err := db.Ping(ctx); err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	migrationCtx, cancelMigrations := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancelMigrations()
	if err := database.RunMigrations(migrationCtx, db); err != nil {
		log.Fatalf("Failed to run database migrations: %v", err)
	}

	// Initialize handlers
	h := handlers.New(cfg, db)

	// Start server
	log.Printf("Starting server on port %s", cfg.Port)
	if err := h.Run(":" + cfg.Port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
