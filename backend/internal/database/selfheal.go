package database

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// HealPharmacyRegistrationEmail restores the pharmacy-level email from its
// registration source of truth.
//
// Task 53 user report: «البريد اللي دخلته وقت التسجيل مجاش بشكل تلقائي للبطاقة
// او للحقول في التعديل». Investigation proved registration always wrote the
// pharmacy email into pharmacies.email (auth service/bootstrap) — but the
// pre-Task-52 branch list read the seeded branch row's contact columns (NULL
// since registration), so edit forms opened with an empty email and every
// main-branch save wiped pharmacies.email via NULLIF(”::...).
//
// The registration-time value survives untouched in accounts.contact_email
// (written once by register/bootstrap, never updated anywhere else), so an
// empty pharmacies.email is restored from it on every application startup —
// healing databases already damaged by the old wipe loop and guarding against
// any future wipe, per the user's expectation that the email entered at
// registration stays authoritative for the card and the edit form.
//
// The statement is idempotent and cheap: it only fills rows whose email is
// empty and only from non-empty registration emails. Runs before the HTTP
// server starts accepting requests.
func HealPharmacyRegistrationEmail(ctx context.Context, db *pgxpool.Pool) error {
	_, err := db.Exec(ctx, `
		UPDATE pharmacies p
		SET    email = a.contact_email,
		       updated_at = NOW()
		FROM   accounts a
		WHERE  p.account_id = a.id
		  AND  a.contact_email IS NOT NULL
		  AND  btrim(a.contact_email) <> ''
		  AND  COALESCE(p.email, '') = ''
	`)
	return err
}
