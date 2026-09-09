package handlers

import (
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// Database migration ledger (سجل ترحيل قاعدة البيانات): GET /pharmacy/system/migrations
// The migrator applies the versioned chain automatically on every backend boot
// (advisory-locked, one transaction per migration, recorded in
// public.schema_migrations). This endpoint exposes the ledger so the settings
// area can show the applied history — the observability half of the
// industry-standard migration workflow (Flyway-style info command).
// ---------------------------------------------------------------------------

func (h *Handler) GetSystemMigrations(c *gin.Context) {
	if _, ok := pharmacyScope(c); !ok {
		return
	}
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT version::text, applied_at
		FROM public.schema_migrations
		ORDER BY version ASC
	`)
	if err != nil {
		log.Printf("[MIGRATIONS] ledger query failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "migrations_query_failed", "message": "تعذر قراءة سجل الترحيلات"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	for rows.Next() {
		var version string
		var appliedAt time.Time
		if err := rows.Scan(&version, &appliedAt); err != nil {
			log.Printf("[MIGRATIONS] ledger scan failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "migrations_query_failed", "message": "تعذر قراءة سجل الترحيلات"})
			return
		}
		items = append(items, gin.H{"version": version, "applied_at": appliedAt})
	}
	if err := rows.Err(); err != nil {
		log.Printf("[MIGRATIONS] ledger rows failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "migrations_query_failed", "message": "تعذر قراءة سجل الترحيلات"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"items": items, "total": len(items)}})
}
