package handlers

import (
        "context"
        "fmt"
        "net/http"
        "os"

        "github.com/gin-gonic/gin"
)

// DebugSchema is a temporary diagnostics endpoint for legacy-schema forensics.
// It is registered only when APP_DEBUG=true and must be disabled (by removing
// APP_DEBUG from the environment) once the hosted database state is confirmed.
func (h *Handler) DebugSchema(c *gin.Context) {
        if os.Getenv("APP_DEBUG") != "true" {
                c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
                return
        }
        ctx := c.Request.Context()
        out := gin.H{}

        rows, err := h.db.Query(ctx, `
                SELECT table_name::text, column_name::text, data_type::text, is_nullable::text,
                       COALESCE(column_default::text, '')
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name IN ('global_products', 'pharmacy_products', 'inventory_batches',
                                     'stock_movements', 'branches', 'pharmacies', 'company_users', 'accounts',
                                     'sales', 'sale_items', 'sale_returns', 'sale_return_items')
                ORDER BY table_name, ordinal_position`)
        if err == nil {
                defer rows.Close()
                cols := make([]gin.H, 0)
                for rows.Next() {
                        var table, column, dataType, nullable, def string
                        if err := rows.Scan(&table, &column, &dataType, &nullable, &def); err == nil {
                                cols = append(cols, gin.H{
                                        "table": table, "column": column, "type": dataType,
                                        "nullable": nullable, "default": def,
                                })
                        }
                }
                out["columns"] = cols
        } else {
                out["columns_error"] = err.Error()
        }

        var viewdef string
        if err := h.db.QueryRow(ctx,
                `SELECT COALESCE(pg_get_viewdef(to_regclass('current_inventory'), true), '')`,
        ).Scan(&viewdef); err == nil {
                out["current_inventory_view"] = viewdef
        } else {
                out["view_error"] = err.Error()
        }

        sample := gin.H{}
        sampleRows, err := h.db.Query(ctx, `SELECT * FROM current_inventory LIMIT 1`)
        if err == nil {
                defer sampleRows.Close()
                fields := sampleRows.FieldDescriptions()
                if sampleRows.Next() {
                        values, _ := sampleRows.Values()
                        for i, v := range values {
                                name := string(fields[i].Name)
                                if err != nil {
                                        sample[name] = "scan_error"
                                        continue
                                }
                                sample[name] = fmt.Sprintf("%T=%v", v, v)
                        }
                }
                sample["_field_types"] = func() []string {
                        names := make([]string, 0, len(fields))
                        for _, f := range fields {
                                names = append(names, string(f.Name))
                        }
                        return names
                }()
        } else {
                sample["error"] = err.Error()
        }
        out["current_inventory_sample"] = sample

        c.JSON(http.StatusOK, out)
        _ = context.Background
}
