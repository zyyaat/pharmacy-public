-- Task 48: per-account UI language preference (professional i18n system).
-- Every principal (company owner or employee) stores its own UI language.
-- Default stays Arabic; the frontend catalogs cover the same allowlist.
ALTER TABLE company_users ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL DEFAULT 'ar';
ALTER TABLE employees    ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL DEFAULT 'ar';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_users_locale_allowed') THEN
        ALTER TABLE company_users ADD CONSTRAINT company_users_locale_allowed
            CHECK (locale IN ('ar', 'en', 'fr', 'es', 'tr', 'zh', 'hi', 'ur'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'employees_locale_allowed') THEN
        ALTER TABLE employees ADD CONSTRAINT employees_locale_allowed
            CHECK (locale IN ('ar', 'en', 'fr', 'es', 'tr', 'zh', 'hi', 'ur'));
    END IF;
END $$;

COMMENT ON COLUMN company_users.locale IS 'UI language preference for the i18n system (Task 48)';
COMMENT ON COLUMN employees.locale    IS 'UI language preference for the i18n system (Task 48)';
