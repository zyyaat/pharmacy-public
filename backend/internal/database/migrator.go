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
                name: "00000000000015_sales_history_returns.sql",
        },
        {
                name: "00000000000016_keep_out_of_stock_visible.sql",
        },
        {
                name: "00000000000017_fuzzy_search_trgm.sql",
        },
        {
                name: "00000000000018_pharmacy_settings.sql",
        },
        {
                name: "00000000000019_sales_discount_customers.sql",
        },
        {
                name: "00000000000020_flexible_permissions.sql",
        },
        {
                name: "00000000000021_account_locale.sql",
        },
        {
                name: "00000000000022_internal_barcode.sql",
        },
        {
                name: "00000000000023_label_settings_permission.sql",
        },
        {
                name: "00000000000024_sale_quantity_snapshot.sql",
        },
        {
                name: "00000000000025_delta_sync.sql",
        },
        {
                name: "00000000000026_saas_plans.sql",
        },
        {
                // Wired retroactively: the file existed on disk but was never
                // in this chain, so payments.idempotency_key (and its
                // replay-protection index) were missing while the manual
                // payment endpoint already referenced the column — any
                // rebuild would 42703 on first manual payment.
                name: "00000000000027_billing_hardening.sql",
        },
        {
                name: "00000000000028_saas_plan_seed_repair.sql",
        },
        {
                // Per-company entitlement overrides (plan baseline + per-account
                // grants/denies/limit tweaks) + the platform audit log table.
                name: "00000000000029_company_entitlements.sql",
        },
        {
                // Platform actions were silently un-audited: the tenant
                // writeAuditLog needs a pharmacy scope a platform principal
                // does not have. This table hosts global billing events with
                // an optional company_id for the per-company logs page.
                name: "00000000000030_platform_audit_logs.sql",
        },
        {
                // Central product libraries: named, country-targeted,
                // versioned catalogs with official prices per library entry,
                // an append-only change log powering pharmacy diffs, and
                // per-pharmacy sync pointers. global_products gains
                // is_verified + source provenance.
                name:          "00000000000031_product_libraries.sql",
                legacyMarkers: []string{"product_libraries", "library_products", "library_changes", "pharmacy_library_syncs"},
        },
        {
                // Payment settlement & subscription reconciliation: separates
                // CONFIRMED (provider captured — webhook/sync/manual) from
                // SETTLED (money reached our bank — operator-verified from
                // the XPay payout batch, since XPay has no payout API/webhook).
                // payment_settlements (one row per online payment) + payments
                // confirmation/failure/review/refund-amount columns + SUB-/PAY-
                // human references via sequence triggers + the event ledger's
                // sync/settlement/review/status_change txn types.
                name:          "00000000000032_payment_settlements.sql",
                legacyMarkers: []string{"payment_settlements"},
        },
        {
                // Support system (live chat + tickets): support_conversations
                // (the per-company chat channel with per-side unread counters
                // and close semantics), append-only support_messages (system
                // rows record lifecycle inside the chat), support_attachments
                // (png/jpeg/webp/pdf <= 2 MiB inline) and support_tickets
                // (TKT-00001 references via sequence trigger, the full
                // open/in_progress/waiting_customer/resolved/closed lifecycle
                // with reopen). Support is never plan-gated.
                name:          "00000000000033_support_system.sql",
                legacyMarkers: []string{"support_conversations", "support_messages", "support_tickets", "support_attachments"},
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

        warnPlanPermissionDrift(ctx, conn)
        return nil
}

// warnPlanPermissionDrift is the permanent lesson of the seed-drift bug
// (migration 26 seeded plan_permissions for free/starter from an empty
// plan_features): a plan whose advertised features are missing their
// enforcement permissions produces exactly the confusing ticket of an
// ACTIVE subscription whose every module API answers
// plan_permission_denied. Detection is automatic and loud; correction is
// NEVER automatic — enforcement data changes go through audited
// migrations or the super admin's plan editor, never through a startup
// side-effect.
func warnPlanPermissionDrift(ctx context.Context, conn *pgxpool.Conn) {
        rows, err := conn.Query(ctx, `
                SELECT pl.slug,
                       array_agg(DISTINCT p2.key ORDER BY p2.key) AS missing
                FROM plans pl
                JOIN plan_features pf ON pf.plan_id = pl.id
                JOIN feature_permissions fp ON fp.feature_key = pf.feature_key
                JOIN permissions p2 ON p2.id = fp.permission_id
                WHERE NOT EXISTS (
                        SELECT 1 FROM plan_permissions pp
                        WHERE pp.plan_id = pl.id
                          AND pp.permission_id = p2.id)
                GROUP BY pl.slug`)
        if err != nil {
                log.Printf("[PLANS] consistency check failed (non-fatal): %v", err)
                return
        }
        defer rows.Close()
        for rows.Next() {
                var slug string
                var missing []string
                if err := rows.Scan(&slug, &missing); err != nil {
                        log.Printf("[PLANS] consistency scan failed (non-fatal): %v", err)
                        return
                }
                log.Printf("[PLANS] WARNING: plan %q advertises features whose permissions are missing (%d): %v — subscribers will see plan_permission_denied; repair via a migration or the plan editor", slug, len(missing), missing)
        }
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
