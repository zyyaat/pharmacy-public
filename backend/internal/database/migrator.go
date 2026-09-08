// Package database contains database bootstrap and migration helpers.
package database

import (
        "context"
        "fmt"
        "log"

        "github.com/jackc/pgx/v5/pgxpool"
        "github.com/pharmacy-os/backend/migrations"
)

const migrationLockKey int64 = 849273641

type migration struct {
        name string
        // legacyMarkers lists tables created by the migration. When a database
        // already contains them but has no ledger row (e.g. a schema applied
        // manually before the runner existed), the migration is adopted instead
        // of replayed. Migrations that only alter existing objects leave this
        // empty so they are always executed when missing from the ledger.
        legacyMarkers []string
}

// migrationChain is the ordered schema history for Pharmacy OS. The
// *_init.sql and *_permissions_system.sql files are legacy placeholders
// from an earlier schema and are intentionally not part of this chain.
var migrationChain = []migration{
        {
                name:          "00000000000001_foundation.sql",
                legacyMarkers: []string{"accounts", "pharmacies", "employees", "branches"},
        },
        {
                name:          "00000000000002_products_inventory.sql",
                legacyMarkers: []string{"global_products", "pharmacy_products", "inventory_batches", "stock_movements"},
        },
        {
                name:          "00000000000003_permissions_auth.sql",
                legacyMarkers: []string{"permissions", "roles", "employee_permissions"},
        },
        {
                name:          "00000000000004_audit_logs.sql",
                legacyMarkers: []string{"audit_logs", "attendance_records"},
        },
        {
                name:          "00000000000005_holding_company.sql",
                legacyMarkers: []string{"companies", "company_users", "company_user_permissions"},
        },
        {
                name:          "00000000000006_go_auth.sql",
                legacyMarkers: []string{"auth_sessions", "auth_email_tokens"},
        },
        {
                name: "00000000000007_inventory_idempotency.sql",
        },
        {
                name: "00000000000008_auth_realms.sql",
        },
        {
                name: "00000000000009_publish_compatible_views.sql",
        },
        {
                name:          "00000000000010_platform_super_admin_singleton.sql",
                legacyMarkers: []string{"platform_bootstrap_state"},
        },
        {
                name:          "00000000000011_packaging_and_sales.sql",
                legacyMarkers: []string{"sales", "sale_items"},
        },
        {
                name:          "00000000000012_platform_trial_settings.sql",
                legacyMarkers: []string{"platform_settings"},
        },
        {
                name: "00000000000013_company_actor_cleanup.sql",
        },
        {
                name: "00000000000014_money_piastres.sql",
        },
        {
                name:          "00000000000015_sales_history_returns.sql",
                legacyMarkers: []string{"sale_returns"},
        },
}

// RunMigrations creates the migration ledger and applies any missing
// migrations. It is safe to call on every application startup.
func RunMigrations(ctx context.Context, db *pgxpool.Pool) error {
        conn, err := db.Acquire(ctx)
        if err != nil {
                return fmt.Errorf("acquire migration connection: %w", err)
        }
        defer conn.Release()

        if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, migrationLockKey); err != nil {
                return fmt.Errorf("lock migrations: %w", err)
        }
        defer func() {
                _, _ = conn.Exec(context.Background(), `SELECT pg_advisory_unlock($1)`, migrationLockKey)
        }()

        if _, err := conn.Exec(ctx, `
                CREATE TABLE IF NOT EXISTS public.schema_migrations (
                        version TEXT PRIMARY KEY,
                        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
        `); err != nil {
                return fmt.Errorf("create migration ledger: %w", err)
        }

        for _, item := range migrationChain {
                applied, err := migrationApplied(ctx, conn, item.name)
                if err != nil {
                        return fmt.Errorf("check migration %s: %w", item.name, err)
                }
                if applied {
                        log.Printf("[MIGRATIONS] Skipping already applied migration %s", item.name)
                        continue
                }

                // Older deployments may already contain the complete schema but not
                // the ledger. In that case, adopt the existing schema instead of
                // replaying non-idempotent legacy SQL against production data.
                if len(item.legacyMarkers) > 0 {
                        exists, err := tablesExist(ctx, conn, item.legacyMarkers)
                        if err != nil {
                                return fmt.Errorf("inspect migration %s: %w", item.name, err)
                        }
                        if exists {
                                if err := recordMigration(ctx, conn, item.name); err != nil {
                                        return fmt.Errorf("record existing migration %s: %w", item.name, err)
                                }
                                log.Printf("[MIGRATIONS] Existing schema detected; recording %s as applied", item.name)
                                continue
                        }
                }

                sqlBytes, err := migrations.FS.ReadFile(item.name)
                if err != nil {
                        return fmt.Errorf("read migration %s: %w", item.name, err)
                }

                tx, err := conn.Begin(ctx)
                if err != nil {
                        return fmt.Errorf("begin migration %s: %w", item.name, err)
                }
                if _, err := tx.Exec(ctx, string(sqlBytes)); err != nil {
                        _ = tx.Rollback(ctx)
                        return fmt.Errorf("execute migration %s: %w", item.name, err)
                }
                if err := tx.Commit(ctx); err != nil {
                        return fmt.Errorf("commit migration %s: %w", item.name, err)
                }
                if err := recordMigration(ctx, conn, item.name); err != nil {
                        return fmt.Errorf("record migration %s: %w", item.name, err)
                }
                log.Printf("[MIGRATIONS] Applied migration %s", item.name)
        }

        return nil
}

func migrationApplied(ctx context.Context, conn *pgxpool.Conn, name string) (bool, error) {
        var applied bool
        err := conn.QueryRow(ctx,
                `SELECT EXISTS (SELECT 1 FROM public.schema_migrations WHERE version = $1)`,
                name,
        ).Scan(&applied)
        return applied, err
}

func recordMigration(ctx context.Context, conn *pgxpool.Conn, name string) error {
        _, err := conn.Exec(ctx, `
                INSERT INTO public.schema_migrations (version)
                VALUES ($1)
                ON CONFLICT (version) DO NOTHING
        `, name)
        return err
}

func tablesExist(ctx context.Context, conn *pgxpool.Conn, tables []string) (bool, error) {
        for _, table := range tables {
                var exists bool
                if err := conn.QueryRow(ctx,
                        `SELECT to_regclass($1) IS NOT NULL`,
                        "public."+table,
                ).Scan(&exists); err != nil {
                        return false, err
                }
                if !exists {
                        return false, nil
                }
        }
        return true, nil
}
