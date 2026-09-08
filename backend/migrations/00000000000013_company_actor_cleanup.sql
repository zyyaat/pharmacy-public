-- Company-owned ledger rows must not become invalid when a company user is
-- removed as part of deleting its owning company.

ALTER TABLE stock_movements
    DROP CONSTRAINT IF EXISTS stock_movements_created_by_company_user_id_fkey;

ALTER TABLE stock_movements
    ADD CONSTRAINT stock_movements_created_by_company_user_id_fkey
    FOREIGN KEY (created_by_company_user_id)
    REFERENCES company_users(id) ON DELETE CASCADE;

ALTER TABLE sales
    DROP CONSTRAINT IF EXISTS sales_company_user_id_fkey;

ALTER TABLE sales
    ADD CONSTRAINT sales_company_user_id_fkey
    FOREIGN KEY (company_user_id)
    REFERENCES company_users(id) ON DELETE CASCADE;