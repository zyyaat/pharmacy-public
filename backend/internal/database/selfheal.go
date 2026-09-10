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
// main-branch save wiped pharmacies.email via NULLIF(''::...).
//
// The registration-time value survives in the company records, which nothing
// updates after registration:
//   - accounts.contact_email (written by the current register/bootstrap flows)
//   - companies.email        (written by every registration era, including the
//     earliest workspace code that predated the accounts table)
//
// so an empty pharmacies.email is restored from the first non-empty source on
// every application startup — healing databases already damaged by the old
// wipe loop and guarding against any future wipe, per the user's expectation
// that the email entered at registration stays authoritative for the card and
// the edit form.
//
// The statement is idempotent and cheap: it only fills rows whose email is
// empty and only from non-empty registration emails. Runs before the HTTP
// server starts accepting requests.
func HealPharmacyRegistrationEmail(ctx context.Context, db *pgxpool.Pool) error {
	_, err := db.Exec(ctx, `
		UPDATE pharmacies p
		SET    email = COALESCE(NULLIF(btrim(a.contact_email), ''), NULLIF(btrim(c.email), '')),
		       updated_at = NOW()
		FROM   accounts a
		JOIN   companies c ON c.id = a.company_id
		WHERE  p.account_id = a.id
		  AND  COALESCE(p.email, '') = ''
		  AND  COALESCE(NULLIF(btrim(a.contact_email), ''), NULLIF(btrim(c.email), '')) IS NOT NULL
	`)
	return err
}
