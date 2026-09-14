package handlers

import (
        "context"
        "encoding/json"
        "log"

        "github.com/jackc/pgx/v5"

        "github.com/pharmacy-os/backend/internal/auth"
)

// writeAuditLog is the first writer for the audit_logs table (migration 4):
// before the barcode feature every audit row source was missing, so the
// table stayed empty. It inserts one immutable audit entry inside the
// caller's transaction so the event is committed (or discarded) atomically
// with the mutation it describes.
//
// RLS note: audit_logs requires app.current_pharmacy_id to be set on the
// session, which every handler transaction already does before calling this.
func writeAuditLog(
        ctx context.Context,
        tx pgx.Tx,
        principal *auth.Principal,
        action, actionCategory, entityType, entityID string,
        newValues map[string]any,
        summary string,
) error {
        // audit_logs.account_id is NOT NULL and references the tenant account;
        // resolve it from the session pharmacy inside the same transaction.
        var accountID string
        if err := tx.QueryRow(ctx,
                `SELECT account_id::text FROM pharmacies WHERE id = $1 AND is_active = true`,
                principal.PharmacyID,
        ).Scan(&accountID); err != nil {
                return err
        }

        employeeID, _ := actorIDs(principal)
        // actor_id references employees(id) only — company-user principals have
        // no employees row, so actor_id stays NULL and the denormalized identity
        // columns (actor_email/actor_display_name) carry the who.
        actorID := employeeID
        if newValues == nil {
                newValues = map[string]any{}
        }
        blob, err := json.Marshal(newValues)
        if err != nil {
                blob = []byte(`{}`)
        }

        if _, err := tx.Exec(ctx, `
                INSERT INTO audit_logs (
                        pharmacy_id, account_id, actor_id, actor_email, actor_display_name,
                        actor_role, action, action_category, entity_type, entity_id,
                        new_values, changes_summary, severity
                ) VALUES (
                        $1::uuid, $2::uuid, NULLIF($3, '')::uuid, $4, $5,
                        $6, $7, $8, $9, NULLIF($10, '')::uuid,
                        $11::jsonb, $12, 'info'
                )
        `, principal.PharmacyID, accountID, actorID, principal.Email, principal.DisplayName,
                principal.Role, action, actionCategory, entityType, entityID,
                string(blob), summary); err != nil {
                return err
        }
        return nil
}

// auditFailure reports an audit write failure without aborting the business
// response path: the mutation already succeeded or the transaction will roll
// back on its own error handling. Losing an audit row is logged loudly so
// operations notices, but a barcode must not become unprintable because the
// audit insert hiccupped.
func auditFailure(scope string, err error) {
        log.Printf("[AUDIT] %s write failed: %v", scope, err)
}

// writePlatformAuditLog records a platform (global SaaS operator) action in
// platform_audit_logs (migration 30). The tenant writeAuditLog can never
// host these events: audit_logs.pharmacy_id is NOT NULL (tenant RLS) and a
// platform principal carries no pharmacy — every billing mutation used to
// fail that lookup silently under `_ =`, so NO platform audit row was ever
// written. companyID links the event to the affected account so the new
// per-company logs page can show one account's history; plan-scope events
// (plan.create/update) pass an empty companyID and land only in the global
// feed.
func writePlatformAuditLog(
        ctx context.Context,
        tx pgx.Tx,
        principal *auth.Principal,
        action, actionCategory, entityType, entityID, companyID string,
        metadata map[string]any,
        summary string,
) error {
        if metadata == nil {
                metadata = map[string]any{}
        }
        blob, err := json.Marshal(metadata)
        if err != nil {
                blob = []byte(`{}`)
        }
        var actorID string
        if principal != nil {
                actorID = principal.ID
        }
        _, err = tx.Exec(ctx, `
                INSERT INTO platform_audit_logs (
                        actor_id, actor_email, actor_display_name, actor_role,
                        action, action_category, entity_type, entity_id, company_id,
                        metadata, changes_summary, severity
                ) VALUES (
                        NULLIF($1, ''), $2, $3, $4,
                        $5, $6, $7, NULLIF($8, ''), NULLIF($9, '')::uuid,
                        $10::jsonb, $11, 'info'
                )
        `, actorID,
                principalEmail(principal), principalName(principal), principalRole(principal),
                action, actionCategory, entityType, entityID, companyID,
                string(blob), summary)
        return err
}

func principalEmail(p *auth.Principal) string {
        if p == nil {
                return ""
        }
        return p.Email
}

func principalName(p *auth.Principal) string {
        if p == nil {
                return ""
        }
        return p.DisplayName
}

func principalRole(p *auth.Principal) string {
        if p == nil {
                return ""
        }
        return p.Role
}
