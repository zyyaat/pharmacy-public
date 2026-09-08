#!/usr/bin/env python3
"""Layer B: sales history + returns (credit notes) verification.

Fresh database -> migrations (01..15) on startup -> real server ->
sell -> list -> detail -> partial returns -> full return -> stock
restored to the EXACT batches -> status transitions -> idempotent
replay -> over-return rejection -> cross-sale rejection.

Every monetary assertion is exact integer arithmetic in piastres.
"""
import os
import signal
import subprocess
import sys
import time
import uuid

import psycopg2
import requests

ROOT = os.path.join(os.path.dirname(__file__), "..")
GO = "/home/z/my-project/sdk/go/bin/go"
SERVER_PORT = 18099
BASE = f"http://127.0.0.1:{SERVER_PORT}/api/v1"
DSN = "postgresql://postgres@127.0.0.1:54329/postgres"
TEST_DB = "sales_history_test"
SERVER_DSN = f"postgresql://postgres@127.0.0.1:54329/{TEST_DB}"

FAILURES = []


def check(name, got, want):
    ok = got == want
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: got={got!r} want={want!r}")
    if not ok:
        FAILURES.append(name)


def main():
    admin = psycopg2.connect(DSN)
    admin.autocommit = True
    cur = admin.cursor()
    cur.execute(f"DROP DATABASE IF EXISTS {TEST_DB}")
    cur.execute(f"CREATE DATABASE {TEST_DB}")

    conn = None
    server = None
    try:
        print("== building server ==")
        subprocess.run([GO, "build", "-o", "/tmp/sales_history_server", "./cmd/server"],
                       cwd=os.path.join(ROOT, "backend"), check=True)

        print("== starting server on fresh DB ==")
        env = dict(os.environ, DATABASE_URL=SERVER_DSN, PORT=str(SERVER_PORT), APP_ENV="development")
        server = subprocess.Popen(["/tmp/sales_history_server"], env=env,
                                  stdout=open("/tmp/sales_history_server.log", "w"),
                                  stderr=subprocess.STDOUT)
        for _ in range(60):
            try:
                if requests.get(f"{BASE}/health", timeout=1).status_code == 200:
                    break
            except requests.RequestException:
                time.sleep(0.5)
        else:
            raise SystemExit("server did not become healthy")
        print("  server healthy (migrations 01..15 applied on startup)")

        s = requests.Session()
        email = f"sales-{uuid.uuid4().hex[:8]}@test.io"
        password = "Str0ng!Pass2026"
        r = s.post(f"{BASE}/auth/register", json={
            "company_name": "Sales Test Co", "company_email": email,
            "first_name": "Test", "last_name": "User",
            "email": email, "password": password,
        }, timeout=10)
        print(f"  register -> {r.status_code}")

        r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": password}, timeout=10)
        if r.status_code != 200:
            conn = psycopg2.connect(SERVER_DSN)
            conn.autocommit = True
            c2 = conn.cursor()
            c2.execute("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (email,))
            r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": password}, timeout=10)
        print(f"  pharmacy login -> {r.status_code}")
        if r.status_code != 200:
            print(r.text)
            raise SystemExit(1)
        csrf = s.cookies.get("pharmacy_csrf")
        headers = {"X-CSRF-Token": csrf} if csrf else {}

        if conn is None:
            conn = psycopg2.connect(SERVER_DSN)
        conn.autocommit = True
        qc = conn.cursor()

        print("== create BOX_STRIP product: box 10500, strip 1750, 2 boxes + 3 strips, cost/strip 1758 ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "بانادول", "generic_name": "Paracetamol", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9800001", "packaging_type": "BOX_STRIP",
            "units_per_box": 6,
            "cost_price_piastres": 10550, "selling_price_piastres": 10500,
            "partial_selling_price_piastres": 1750,
            "min_stock_level": 0, "initial_boxes": 2, "initial_strips": 3,
            "batch_number": "B1", "expiry_date": "2027-01-01",
        }, timeout=10)
        check("product created", r.status_code, 201)
        product1 = r.json()["data"]["id"]

        print("== sale 1: 2 boxes + 3 strips = 26250 ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sh-sale-1-aaaaaaaa",
            "items": [
                {"pharmacy_product_id": product1, "sale_unit": "box", "quantity": 2},
                {"pharmacy_product_id": product1, "sale_unit": "strip", "quantity": 3},
            ],
        }, timeout=15)
        check("sale 201", r.status_code, 201)
        check("total 26250", r.json()["data"]["total_amount_piastres"], 26250)
        sale1 = r.json()["data"]["sale_id"]
        qc.execute("SELECT ROUND(quantity)::bigint FROM inventory_batches WHERE pharmacy_product_id=%s", (product1,))
        check("stock drained to 0", qc.fetchone()[0], 0)

        print("== sales list shows the invoice ==")
        r = s.get(f"{BASE}/pharmacy/pos/sales", timeout=10)
        check("list 200", r.status_code, 200)
        page = r.json()["data"]
        check("total 1", page["total"], 1)
        row = page["sales"][0]
        check("invoice_number 1", row["invoice_number"], 1)
        check("status completed", row["status"], "completed")
        check("total 26250", row["total_amount_piastres"], 26250)
        check("no returns yet", row["returns"], [])

        print("== search by product name ==")
        r = s.get(f"{BASE}/pharmacy/pos/sales", params={"search": "بانادول"}, timeout=10)
        check("search finds it", r.json()["data"]["total"], 1)
        r = s.get(f"{BASE}/pharmacy/pos/sales", params={"search": "مفيش"}, timeout=10)
        check("search empty", r.json()["data"]["total"], 0)

        print("== sale detail: rows with returnable quantities ==")
        r = s.get(f"{BASE}/pharmacy/pos/sales/{sale1}", timeout=10)
        check("detail 200", r.status_code, 200)
        detail = r.json()["data"]
        items = detail["items"]
        check("2 sale rows", len(items), 2)
        box_row = next(i for i in items if i["sale_unit"] == "box")
        strip_row = next(i for i in items if i["sale_unit"] == "strip")
        check("box row: 12 strips, amount 21000", (box_row["quantity_base"], box_row["amount_piastres"]), (12, 21000))
        check("strip row: 3 strips, amount 5250", (strip_row["quantity_base"], strip_row["amount_piastres"]), (3, 5250))
        check("box returnable 12", box_row["returnable_quantity_base"], 12)
        check("strip returnable 3", strip_row["returnable_quantity_base"], 3)
        check("batch number surfaced", box_row["batch_number"], "B1")

        print("== partial return: 2 strips from the strip row (exact allocation) ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale1}/returns", headers=headers, json={
            "idempotency_key": "sh-ret-1-aaaaaaaaaa",
            "reason": "المريض غيّر رأيه",
            "items": [{"sale_item_id": strip_row["sale_item_id"], "quantity": 2}],
        }, timeout=15)
        check("return 201", r.status_code, 201)
        ret1 = r.json()["data"]
        check("refund 2/3 of 5250 = 3500", ret1["total_amount_piastres"], 3500)
        check("return_number 1", ret1["return_number"], 1)
        check("sale status partially_returned", ret1["sale_status"], "partially_returned")
        qc.execute("SELECT ROUND(quantity)::bigint FROM inventory_batches WHERE pharmacy_product_id=%s", (product1,))
        check("stock 0 -> 2", qc.fetchone()[0], 2)
        qc.execute("SELECT COUNT(*) FROM stock_movements WHERE movement_type='return_from_customer' AND reason='pos_return'")
        check("1 return movement", qc.fetchone()[0], 1)

        print("== chained partial return: last strip refunds the exact remaining 1750 ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale1}/returns", headers=headers, json={
            "items": [{"sale_item_id": strip_row["sale_item_id"], "quantity": 1}],
        }, timeout=15)
        check("return 201", r.status_code, 201)
        check("refund remaining 1750", r.json()["data"]["total_amount_piastres"], 1750)
        qc.execute("SELECT ROUND(quantity)::bigint FROM inventory_batches WHERE pharmacy_product_id=%s", (product1,))
        check("stock 3", qc.fetchone()[0], 3)

        print("== over-return rejected: 409 return_exceeds_sold ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale1}/returns", headers=headers, json={
            "items": [{"sale_item_id": strip_row["sale_item_id"], "quantity": 1}],
        }, timeout=15)
        check("over-return 409", r.status_code, 409)
        check("error code", r.json().get("error"), "return_exceeds_sold")
        check("returnable reported 0", r.json()["data"]["returnable_quantity_base"], 0)

        print("== idempotent replay of return 1 ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale1}/returns", headers=headers, json={
            "idempotency_key": "sh-ret-1-aaaaaaaaaa",
            "reason": "المريض غيّر رأيه",
            "items": [{"sale_item_id": strip_row["sale_item_id"], "quantity": 2}],
        }, timeout=15)
        check("replay 200", r.status_code, 200)
        check("replayed flag", r.json()["data"]["replayed"], True)
        check("same return id", r.json()["data"]["return_id"], ret1["return_id"])
        qc.execute("SELECT COUNT(*) FROM sale_returns WHERE idempotency_key=%s", ("sh-ret-1-aaaaaaaaaa",))
        check("replay created no second credit note", qc.fetchone()[0], 1)

        print("== full return of the box row: refund exactly 21000, status returned ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale1}/returns", headers=headers, json={
            "reason": "استرجاع كامل",
            "items": [{"sale_item_id": box_row["sale_item_id"], "quantity": 12}],
        }, timeout=15)
        check("box return 201", r.status_code, 201)
        check("refund 21000", r.json()["data"]["total_amount_piastres"], 21000)
        check("status returned", r.json()["data"]["sale_status"], "returned")
        qc.execute("SELECT ROUND(quantity)::bigint FROM inventory_batches WHERE pharmacy_product_id=%s", (product1,))
        check("stock fully restored to 15", qc.fetchone()[0], 15)

        qc.execute("""
            SELECT COALESCE(SUM(total_amount_piastres),0) FROM sale_returns WHERE sale_id=%s
        """, (sale1,))
        check("credit notes sum exactly to the invoice 26250", qc.fetchone()[0], 26250)
        qc.execute("SELECT status FROM sales WHERE id=%s", (sale1,))
        check("DB status returned", qc.fetchone()[0], "returned")

        print("== cross-sale return rejected ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sh-sale-2-bbbbbbbb",
            "items": [{"pharmacy_product_id": product1, "sale_unit": "strip", "quantity": 1}],
        }, timeout=15)
        check("sale 2 created", r.status_code, 201)
        sale2 = r.json()["data"]["sale_id"]
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale2}/returns", headers=headers, json={
            "items": [{"sale_item_id": box_row["sale_item_id"], "quantity": 1}],
        }, timeout=15)
        check("foreign sale_item 404", r.status_code, 404)
        check("error code", r.json().get("error"), "return_item_not_found")

        print("== history list reflects everything ==")
        r = s.get(f"{BASE}/pharmacy/pos/sales/{sale1}", timeout=10)
        detail = r.json()["data"]
        check("sale detail status returned", detail["sale"]["status"], "returned")
        check("returned total 26250", detail["sale"]["returned_amount_piastres"], 26250)
        check("3 return documents", len(detail["sale"]["returns"]), 3)
        check("no returnable rows left", sum(i["returnable_quantity_base"] for i in detail["items"]), 0)
        r = s.get(f"{BASE}/pharmacy/pos/sales", timeout=10)
        rows = {row["id"]: row for row in r.json()["data"]["sales"]}
        check("sale1 status in list", rows[sale1]["status"], "returned")
        check("sale2 status completed", rows[sale2]["status"], "completed")
        check("sale2 returned amount 0", rows[sale2]["returned_amount_piastres"], 0)

        print("== cross-batch partial return: box sold over [5,1] strips, refund allocation exact ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "بروفين", "generic_name": "Ibuprofen", "dosage_form": "tablet",
            "strength": "400mg", "barcode": "9800002", "packaging_type": "BOX_STRIP",
            "units_per_box": 6,
            "cost_price_piastres": 9000, "selling_price_piastres": 10700,
            "partial_selling_price_piastres": 1783,
            "min_stock_level": 0, "initial_boxes": 0, "initial_strips": 5,
            "batch_number": "B-MAIN", "expiry_date": "2027-01-01",
        }, timeout=10)
        check("product 2 created", r.status_code, 201)
        product2 = r.json()["data"]["id"]
        qc.execute("SELECT id FROM branches WHERE is_active = true LIMIT 1")
        branch_id = qc.fetchone()[0]
        qc.execute(
            "INSERT INTO inventory_batches (pharmacy_product_id, branch_id, batch_number, quantity, unit, cost_per_unit, received_by, reference_type) "
            "VALUES (%s, %s, 'B-SPLIT', 7, 'strip'::unit_type, 1500, NULL, 'opening_balance')",
            (product2, branch_id))

        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sh-sale-3-cccccccc",
            "items": [{"pharmacy_product_id": product2, "sale_unit": "box", "quantity": 1}],
        }, timeout=15)
        check("fragmented sale 201", r.status_code, 201)
        sale3 = r.json()["data"]["sale_id"]
        check("line total 10700", r.json()["data"]["total_amount_piastres"], 10700)
        qc.execute("SELECT id::text, amount_piastres, ROUND(quantity)::bigint FROM sale_items WHERE sale_id=%s ORDER BY amount_piastres", (sale3,))
        rows3 = qc.fetchall()
        check("2 batch rows", len(rows3), 2)
        check("allocation [1783, 8917] sums 10700", [r[1] for r in rows3], [1783, 8917])
        # FEFO: B-MAIN (5 strips, earlier expiry date same day) drains first? B-MAIN created
        # before B-SPLIT; both expiry 2027-01-01; order by received_date, created_at.
        row_small, row_big = rows3  # amounts sorted ascending
        r = s.get(f"{BASE}/pharmacy/pos/sales/{sale3}", timeout=10)
        items3 = r.json()["data"]["items"]
        item_by_amount = {i["amount_piastres"]: i for i in items3}
        # The frontend distributes the returned strips across rows itself:
        # return "1 box" = 6 strips as [row1 full, row2 full] -> refund exactly 10700
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale3}/returns", headers=headers, json={
            "reason": "كسر في التغليف",
            "items": [
                {"sale_item_id": item_by_amount[1783]["sale_item_id"], "quantity": 1},
                {"sale_item_id": item_by_amount[8917]["sale_item_id"], "quantity": 5},
            ],
        }, timeout=15)
        check("cross-batch full return 201", r.status_code, 201)
        check("refund exactly 10700", r.json()["data"]["total_amount_piastres"], 10700)
        qc.execute("SELECT ROUND(SUM(quantity))::bigint FROM inventory_batches WHERE pharmacy_product_id=%s", (product2,))
        check("stock restored to 12", qc.fetchone()[0], 12)

        print("== return on legacy NULL-strip-price product (fallback price path) ==")
        qc.execute(
            "INSERT INTO global_products (name, dosage_form, default_unit, product_category, requires_prescription, is_active, barcode) "
            "VALUES ('ليجسي', 'tablet'::dosage_form, 'strip'::unit_type, 'medication'::product_category, 'no'::prescription_required, true, '9800003') RETURNING id")
        gp4 = qc.fetchone()[0]
        qc.execute(
            "INSERT INTO pharmacy_products (pharmacy_id, global_product_id, cost_price, selling_price, partial_selling_price, "
            "packaging_type, units_per_box, min_stock_level, is_active) "
            "VALUES ((SELECT pharmacy_id FROM branches WHERE id=%s), %s, 600, 4000, NULL, 'BOX_STRIP', 5, 0, true) RETURNING id",
            (branch_id, gp4))
        product4 = qc.fetchone()[0]
        qc.execute(
            "INSERT INTO inventory_batches (pharmacy_product_id, branch_id, batch_number, quantity, unit, cost_per_unit, received_by, reference_type) "
            "VALUES (%s, %s, 'LEGACY', 10, 'strip'::unit_type, 600, NULL, 'opening_balance')",
            (product4, branch_id))
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sh-sale-4-dddddddd",
            "items": [{"pharmacy_product_id": product4, "sale_unit": "strip", "quantity": 4}],
        }, timeout=15)
        check("legacy sale 201 (4 x 800 fallback = 3200)", r.json()["data"]["total_amount_piastres"], 3200)
        sale4 = r.json()["data"]["sale_id"]
        qc.execute("SELECT id::text FROM sale_items WHERE sale_id=%s LIMIT 1", (sale4,))
        legacy_item = qc.fetchone()[0]
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale4}/returns", headers=headers, json={
            "items": [{"sale_item_id": legacy_item, "quantity": 3}],
        }, timeout=15)
        check("legacy partial return 201", r.status_code, 201)
        # 3200 remaining, [3,1]: exact 3/4 = 2400
        check("refund 3/4 of 3200 = 2400", r.json()["data"]["total_amount_piastres"], 2400)
        qc.execute("SELECT ROUND(quantity)::bigint FROM inventory_batches WHERE pharmacy_product_id=%s", (product4,))
        check("legacy stock 10-4+3=9", qc.fetchone()[0], 9)

        print("== return without CSRF token rejected ==")
        r = requests.post(f"{BASE}/pharmacy/pos/sales/{sale2}/returns", cookies=s.cookies, json={
            "items": [{"sale_item_id": legacy_item, "quantity": 1}],
        }, timeout=10)
        check("no-csrf rejected", r.status_code in (401, 403), True)

        print("== unauthenticated list rejected ==")
        r = requests.get(f"{BASE}/pharmacy/pos/sales", timeout=10)
        check("anon list 401", r.status_code, 401)

    finally:
        if server is not None:
            server.send_signal(signal.SIGTERM)
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
        if conn is not None:
            conn.close()
        time.sleep(0.5)
        cur.execute(f"DROP DATABASE IF EXISTS {TEST_DB}")
        admin.close()

    if FAILURES:
        print(f"\nRESULT: {len(FAILURES)} FAILURES: {FAILURES}")
        sys.exit(1)
    print("\nRESULT: ALL SALES HISTORY + RETURNS CHECKS PASSED")


if __name__ == "__main__":
    main()
