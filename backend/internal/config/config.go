// Package config handles application configuration
// Supports: PostgreSQL, Go-managed authentication, River Queue, Application Settings
package config

import (
	"fmt"
	"log"
	urlpkg "net/url"
	"os"
	"strings"
	"time"
)

// Config holds all application configuration
type Config struct {
	// Server
	Port        string
	Environment string // "development", "staging", "production"

	// Database (PostgreSQL via Supavisor)
	DatabaseURL string // Format: postgresql://user:pass@host:port/dbname

	// Go-managed Authentication
	AuthAccessTTL  time.Duration
	AuthRefreshTTL time.Duration
	CookieSecure   bool
	CookieDomain   string

	// Transactional email (Brevo HTTP API)
	BrevoAPIKey   string
	MailFromEmail string
	MailFromName  string
	PublicAppURL  string

	// River Queue (Postgres-based job queue)
	RiverDSN string

	// Application Settings
	LogLevel       string // "debug", "info", "warn", "error"
	CorsOrigins    string // Comma-separated list of allowed origins
	MaxRequestSize int64  // Max request body size in bytes (default: 10MB)

	// One-time production bootstrap for the initial platform administrator.
	BootstrapSuperAdminEmail     string
	BootstrapSuperAdminPassword  string
	BootstrapSuperAdminFirstName string
	BootstrapSuperAdminLastName  string
	BootstrapSuperAdminCompany   string
}

// Load reads configuration from environment variables with sensible defaults
func Load() *Config {
	databaseURL := getEnv("DATABASE_URL", "postgresql://postgres:postgres@localhost:6543/postgres")
	cfg := &Config{
		// Server
		// Priority: PORT (DockHosting/standard) > BACKEND_PORT (custom) > 8080 (default)
		Port:        getEnv("PORT", getEnv("BACKEND_PORT", "8080")),
		Environment: getEnv("APP_ENV", "development"),

		// Database - Default to Supavisor port 6543
		DatabaseURL: databaseURL,

		// Go-managed Authentication
		AuthAccessTTL:  15 * time.Minute,
		AuthRefreshTTL: 30 * 24 * time.Hour,
		CookieSecure:   getEnv("APP_ENV", "development") == "production" || getEnvBool("AUTH_COOKIE_SECURE", false),
		CookieDomain:   getEnv("AUTH_COOKIE_DOMAIN", ""),

		// Transactional email
		BrevoAPIKey:   getEnv("BREVO_API_KEY", ""),
		MailFromEmail: getEnv("MAIL_FROM_EMAIL", ""),
		MailFromName:  getEnv("MAIL_FROM_NAME", "Pharmacy OS"),
		PublicAppURL:  getEnv("PUBLIC_APP_URL", ""),

		// River Queue
		RiverDSN: getEnv("RIVER_DSN", databaseURL),

		// Application Settings
		LogLevel:       getEnv("LOG_LEVEL", "info"),
		CorsOrigins:    getEnv("CORS_ORIGINS", "http://localhost:3000,http://localhost:3001"),
		MaxRequestSize: getEnvAsInt64("MAX_REQUEST_SIZE", 10*1024*1024), // 10MB default

		BootstrapSuperAdminEmail:     getEnv("BOOTSTRAP_SUPER_ADMIN_EMAIL", ""),
		BootstrapSuperAdminPassword:  getEnv("BOOTSTRAP_SUPER_ADMIN_PASSWORD", ""),
		BootstrapSuperAdminFirstName: getEnv("BOOTSTRAP_SUPER_ADMIN_FIRST_NAME", "Mohamed"),
		BootstrapSuperAdminLastName:  getEnv("BOOTSTRAP_SUPER_ADMIN_LAST_NAME", "Admin"),
		BootstrapSuperAdminCompany:   getEnv("BOOTSTRAP_SUPER_ADMIN_COMPANY", "Pharmacy OS"),
	}

	// Log important configuration for debugging
	log.Printf("[CONFIG] Port: %s, Environment: %s, DatabaseURL: %s",
		cfg.Port, cfg.Environment, maskDatabaseURL(cfg.DatabaseURL))

	return cfg
}

// maskDatabaseURL masks sensitive parts of the database URL for logging
func maskDatabaseURL(url string) string {
	if url == "" {
		return "(empty)"
	}

	parsed, err := urlpkg.Parse(url)
	if err != nil || parsed.User == nil {
		return "[redacted database URL]"
	}

	parsed.User = urlpkg.UserPassword(parsed.User.Username(), "***")
	return parsed.String()
}

// IsProduction returns true if running in production mode
func (c *Config) IsProduction() bool {
	return c.Environment == "production"
}

// IsDevelopment returns true if running in development mode
func (c *Config) IsDevelopment() bool {
	return c.Environment == "development"
}

// Validate checks if required configuration is present
func (c *Config) Validate() error {
	var errors []string

	if c.DatabaseURL == "" {
		errors = append(errors, "DATABASE_URL is required")
	}
	if c.IsProduction() {
		if strings.TrimSpace(os.Getenv("CORS_ORIGINS")) == "" {
			errors = append(errors, "CORS_ORIGINS is required in production")
		}
		if strings.TrimSpace(c.PublicAppURL) == "" {
			errors = append(errors, "PUBLIC_APP_URL is required in production")
		}
		if strings.TrimSpace(c.BootstrapSuperAdminEmail) == "" {
			errors = append(errors, "BOOTSTRAP_SUPER_ADMIN_EMAIL is required in production")
		}
	}

	if len(errors) > 0 {
		return fmt.Errorf("configuration errors: %v", errors)
	}

	return nil
}

func getEnvBool(key string, defaultValue bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value == "1" || value == "true" || value == "TRUE" || value == "yes"
}

// GetCorsOrigins returns CORS origins as a slice
func (c *Config) GetCorsOrigins() []string {
	if c.CorsOrigins == "" {
		return []string{"*"}
	}

	origins := make([]string, 0)
	for _, origin := range splitString(c.CorsOrigins, ",") {
		if trimmed := strings.TrimRight(trimSpace(origin), "/"); trimmed != "" {
			origins = append(origins, trimmed)
		}
	}

	if len(origins) == 0 {
		return []string{"*"}
	}

	return origins
}

// Helper functions for environment variable parsing

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvAsInt64(key string, defaultValue int64) int64 {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}

	var result int64
	_, err := fmt.Sscanf(value, "%d", &result)
	if err != nil {
		return defaultValue
	}
	return result
}

func splitString(s, separator string) []string {
	result := make([]string, 0)
	start := 0

	for i := 0; i < len(s); i++ {
		if string(s[i]) == separator {
			result = append(result, s[start:i])
			start = i + 1
		}
	}

	result = append(result, s[start:])
	return result
}

func trimSpace(s string) string {
	// Simple trim implementation
	start := 0
	end := len(s) - 1

	for start <= end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r') {
		start++
	}

	for end >= start && (s[end] == ' ' || s[end] == '\t' || s[end] == '\n' || s[end] == '\r') {
		end--
	}

	if start > end {
		return ""
	}

	return s[start : end+1]
}
