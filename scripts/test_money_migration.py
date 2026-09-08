#!/usr/bin/env python3
"""Layer A: verify migration 14 converts legacy fractional money exactly.

Applies migrations 01..13 to a throwaway database, inserts legacy-shaped
rows (numeric prices in EGP), then applies migration 14 and asserts every
value was scaled by exactly 100, the generated column was rebuilt, the view
was recreated, and re-running the migration is a no-op.
"""
import glob
import os
import sys

import psycopg2

BASE = os.path.join(os.path.dirname(__file__), "..", "backend", "migrations")
DSN_CANDIDATES = [
    "postgresql://postgres@127.0.0.1:54329/postgres",
    "postgresql://postgres:postgres@127.0.0.1:54329/postgres",
]
DB = "money_migration_test"

CHAIN = [
    "00000000000001_foundation.sql",
    "00000000000002_products_inventory.sql",
    "00000000000003_permissions_auth.sql",
    "00000000000004_audit_logs.sql",
    "00000000000005_holding_company.sql",
    "00000000000006_go_auth.sql",
    "00000000000007_inventory_idempotency.sql",
    "00000000000008_auth_realms.sql",
    "00000000000009_publish_compatible_views.sql",
    "00000000000010_platform_super_admin_singleton.sql",
    "00000000000011_packaging_and_sales.sql",
    "00000000000012_platform_trial_settings.sql",
    "00000000000013_company_actor_cleanup.sql",
]
M14 = "00000000000014_money_piastres.sql"

FAILURES = []


def check(name, got, want):
    ok = got == want
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: got={got!r} want={want!r}")
    if not ok:
        FAILURES.append(name)


def connect_admin():
    last = None
    for dsn in DSN_CANDIDATES:
        try:
            conn = psycopg2.connect(dsn)
            conn.autocommit = True
            print(f"admin connected via {dsn.split('@')[1]}")
            return conn
        except psycopg2.Error as exc:
            last = exc
    raise SystemExit(f"cannot connect to local postgres: {last}")


def apply_file(cur, path):
    sql = open(path).read()
    cur.execute(sql)


def main():
    admin = connect_admin()
    cur = admin.cursor()
    cur.execute(f"DROP DATABASE IF EXISTS {DB}")
    cur.execute(f"CREATE DATABASE {DB}")

    conn = psycopg2.connect(f"postgresql://postgres@127.0.0.1:54329/{DB}")
    conn.autocommit = True
    cur = conn.cursor()

    print("== applying legacy chain 01..13 ==")
    for name in CHAIN:
        apply_file(cur, os.path.join(BASE, name))
        print(f"  applied {name}")

    print("== inserting legacy-shaped rows (money as fractional EGP) ==")
    cur.execute("INSERT INTO accounts (company_name, contact_email) VALUES ('Test Co', 'test@example.com') RETURNING id")
    account_id = cur.fetchone()[0]
    cur.execute("INSERT INTO pharmacies (account_id, name) VALUES (%s, 'صيدلية الاختبار') RETURNING id", (account_id,))
    pharmacy_id = cur.fetchone()[0]
    cur.execute("INSERT INTO branches (pharmacy_id, name) VALUES (%s, 'الفرع الرئيسي') RETURNING id", (pharmacy_id,))
    branch_id = cur.fetchone()[0]
    cur.execute(
        "INSERT INTO employees (account_id, pharmacy_id, email, first_name, last_name, status) VALUES (%s, %s, 't@t.io', 'مصطفى', 'ع', 'active') RETURNING id",
        (account_id, pharmacy_id),
    )
    employee_id = cur.fetchone()[0]
    cur.execute(
        "INSERT INTO global_products (name, dosage_form, default_unit, product_category, requires_prescription, is_active, barcode) "
        "VALUES ('بانادول', 'tablet'::dosage_form, 'strip'::unit_type, 'medication'::product_category, 'no'::prescription_required, true, '9000001') RETURNING id"
    )
    global_id = cur.fetchone()[0]
    cur.execute(
        "INSERT INTO pharmacy_products (pharmacy_id, global_product_id, cost_price, selling_price, partial_selling_price, "
        "packaging_type, units_per_box, min_stock_level, is_active) "
        "VALUES (%s, %s, 80.5000, 105.5000, NULL, 'BOX_STRIP', 6, 3.0000, true) RETURNING id",
        (pharmacy_id, global_id),
    )
    product_id = cur.fetchone()[0]
    cur.execute(
        "INSERT INTO inventory_batches (pharmacy_product_id, branch_id, batch_number, quantity, unit, cost_per_unit, received_by, reference_type) "
        "VALUES (%s, %s, 'LEGACY-1', 25.0000, 'strip'::unit_type, 6.0000, %s, 'opening_balance') RETURNING id",
        (product_id, branch_id, employee_id),
    )
    batch_id = cur.fetchone()[0]
    cur.execute(
        "INSERT INTO stock_movements (batch_id, movement_type, quantity, unit, quantity_before, quantity_after, unit_cost, total_cost, created_by, reason) "
        "VALUES (%s, 'purchase'::movement_type, 25.0000, 'strip'::unit_type, 0, 25.0000, 6.0000, 150.0000, %s, 'opening_balance')",
        (batch_id, employee_id),
    )
    cur.execute(
        "INSERT INTO sales (pharmacy_id, branch_id, employee_id, total_amount) VALUES (%s, %s, %s, 262.50) RETURNING id",
        (pharmacy_id, branch_id, employee_id),
    )
    sale_id = cur.fetchone()[0]
    cur.execute(
        "INSERT INTO sale_items (sale_id, pharmacy_product_id, batch_id, sale_unit, quantity, base_quantity, unit_price, unit_cost) "
        "VALUES (%s, %s, %s, 'box', 2.0000, 12.0000, 105.5000, 6.0000)",
        (sale_id, product_id, batch_id),
    )

    print("== applying migration 14 (money -> piastres BIGINT) ==")
    apply_file(cur, os.path.join(BASE, M14))

    def scalar(sql, params=None):
        cur.execute(sql, params or ())
        return cur.fetchone()[0]

    def coltype(table, column):
        cur.execute(
            "SELECT data_type FROM information_schema.columns WHERE table_schema='public' AND table_name=%s AND column_name=%s",
            (table, column),
        )
        return cur.fetchone()[0]

    print("== asserting exact conversion ==")
    check("pharmacy_products.selling_price type", coltype("pharmacy_products", "selling_price"), "bigint")
    check("pharmacy_products.selling_price = 10550", scalar("SELECT selling_price FROM pharmacy_products WHERE id=%s", (product_id,)), 10550)
    check("pharmacy_products.cost_price = 8050", scalar("SELECT cost_price FROM pharmacy_products WHERE id=%s", (product_id,)), 8050)
    check("pharmacy_products.partial NULL kept", scalar("SELECT partial_selling_price FROM pharmacy_products WHERE id=%s", (product_id,)), None)
    check("min_stock_level stays numeric (quantity domain)", coltype("pharmacy_products", "min_stock_level"), "numeric")

    check("inventory_batches.cost_per_unit = 600", scalar("SELECT cost_per_unit FROM inventory_batches WHERE id=%s", (batch_id,)), 600)
    check("inventory_batches.total_cost rebuilt bigint", coltype("inventory_batches", "total_cost"), "bigint")
    check("inventory_batches.total_cost = 25*600", scalar("SELECT total_cost FROM inventory_batches WHERE id=%s", (batch_id,)), 15000)

    check("sales.total_amount = 26250", scalar("SELECT total_amount FROM sales WHERE id=%s", (sale_id,)), 26250)
    check("sale_items.unit_price = 10550", scalar("SELECT unit_price FROM sale_items WHERE sale_id=%s", (sale_id,)), 10550)
    check("sale_items.amount_piastres backfilled = 21100", scalar("SELECT amount_piastres FROM sale_items WHERE sale_id=%s", (sale_id,)), 21100)
    check("sale_items.cost_amount_piastres = 7200", scalar("SELECT cost_amount_piastres FROM sale_items WHERE sale_id=%s", (sale_id,)), 7200)
    check("stock_movements.unit_cost = 600", scalar("SELECT unit_cost FROM stock_movements WHERE batch_id=%s", (batch_id,)), 600)
    check("stock_movements.total_cost = 15000", scalar("SELECT total_cost FROM stock_movements WHERE batch_id=%s AND movement_type='purchase'", (batch_id,)), 15000)
    check("pharmacies.currency_minor_unit = 2", scalar("SELECT currency_minor_unit FROM pharmacies WHERE id=%s", (pharmacy_id,)), 2)
    check("sales.idempotency_key column exists", scalar("SELECT COUNT(*) FROM information_schema.columns WHERE table_name='sales' AND column_name='idempotency_key'"), 1)
    check("current_inventory view recreated", scalar("SELECT COUNT(*) FROM pg_views WHERE viewname='current_inventory'"), 1)
    check("view reads money as bigint", scalar("SELECT pg_typeof(selling_price)::text FROM current_inventory LIMIT 1"), "bigint")

    print("== generated column recomputes for new rows ==")
    cur.execute(
        "INSERT INTO inventory_batches (pharmacy_product_id, branch_id, batch_number, quantity, unit, cost_per_unit, received_by, reference_type) "
        "VALUES (%s, %s, 'NEW-2', 10, 'strip'::unit_type, 600, %s, 'opening_balance') RETURNING id",
        (product_id, branch_id, employee_id),
    )
    batch2 = cur.fetchone()[0]
    check("new batch total_cost = 10*600", scalar("SELECT total_cost FROM inventory_batches WHERE id=%s", (batch2,)), 6000)

    print("== idempotency: applying migration 14 again must not rescale ==")
    apply_file(cur, os.path.join(BASE, M14))
    check("selling_price still 10550 after re-run", scalar("SELECT selling_price FROM pharmacy_products WHERE id=%s", (product_id,)), 10550)
    check("sales.total still 26250 after re-run", scalar("SELECT total_amount FROM sales WHERE id=%s", (sale_id,)), 26250)
    check("cost_per_unit still 600 after re-run", scalar("SELECT cost_per_unit FROM inventory_batches WHERE id=%s", (batch2,)), 600)

    cur.execute("DROP VIEW IF EXISTS current_inventory")
    conn.close()
    cur = admin.cursor()
    cur.execute(f"DROP DATABASE IF EXISTS {DB}")
    admin.close()
    if FAILURES:
        print(f"\nRESULT: {len(FAILURES)} FAILURES: {FAILURES}")
        sys.exit(1)
    print("\nRESULT: ALL MONEY MIGRATION CHECKS PASSED")


if __name__ == "__main__":
    main()
