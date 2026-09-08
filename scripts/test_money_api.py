#!/usr/bin/env python3
"""Layer B: end-to-end money verification against a real backend.

Fresh database -> migrations run on server startup -> register -> login ->
create product in piastres -> barcode lookup -> POS checkout with intent
prices -> fragmented-batch allocation (exact remainder distribution) ->
idempotent replay -> 409 price_changed -> insufficient stock -> dashboard
inventory shape.

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
TEST_DB = "money_api_test"
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
        subprocess.run([GO, "build", "-o", "/tmp/money_api_server", "./cmd/server"],
                       cwd=os.path.join(ROOT, "backend"), check=True)

        print("== starting server on fresh DB ==")
        env = dict(os.environ, DATABASE_URL=SERVER_DSN, PORT=str(SERVER_PORT), APP_ENV="development")
        server = subprocess.Popen(["/tmp/money_api_server"], env=env,
                                  stdout=open("/tmp/money_api_server.log", "w"),
                                  stderr=subprocess.STDOUT)
        for _ in range(60):
            try:
                if requests.get(f"{BASE}/health", timeout=1).status_code == 200:
                    break
            except requests.RequestException:
                time.sleep(0.5)
        else:
            raise SystemExit("server did not become healthy")
        print("  server healthy (migrations applied on startup)")

        s = requests.Session()
        email = f"money-{uuid.uuid4().hex[:8]}@test.io"
        password = "Str0ng!Pass2026"
        r = s.post(f"{BASE}/auth/register", json={
            "company_name": "Money Test Co", "company_email": email,
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
            print(f"  forced email_verified_at on company_users ({c2.rowcount} rows)")
            r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": password}, timeout=10)
        print(f"  pharmacy login -> {r.status_code}")
        if r.status_code != 200:
            print(r.text); raise SystemExit(1)
        csrf = s.cookies.get("pharmacy_csrf")
        headers = {"X-CSRF-Token": csrf} if csrf else {}

        if conn is None:
            conn = psycopg2.connect(SERVER_DSN)
        conn.autocommit = True
        qc = conn.cursor()

        r = s.get(f"{BASE}/pharmacy/context", timeout=10)
        check("pharmacy context ok", r.status_code, 200)

        print("== create product (prices in piastres) ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "بانادول", "generic_name": "Paracetamol", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9900001", "packaging_type": "BOX_STRIP",
            "units_per_box": 6,
            "cost_price_piastres": 10550, "selling_price_piastres": 10500,
            "partial_selling_price_piastres": 1750,
            "min_stock_level": 3, "initial_boxes": 2, "initial_strips": 3,
            "batch_number": "B1", "expiry_date": "2027-01-01",
        }, timeout=10)
        print(f"  create -> {r.status_code}")
        check("product created", r.status_code, 201)
        check("initial base quantity 2*6+3=15", r.json()["data"]["initial_base_quantity"], 15)
        product_id = r.json()["data"]["id"]

        print("== barcode lookup returns integer piastres ==")
        r = s.get(f"{BASE}/pharmacy/pos/products", params={"barcode": "9900001"}, timeout=10)
        data = r.json()["data"]
        check("lookup 200", r.status_code, 200)
        check("selling_price_piastres", data["selling_price_piastres"], 10500)
        check("partial_selling_price_piastres", data["partial_selling_price_piastres"], 1750)
        check("stock", data["stock"], 15)

        print("== checkout 1: 2 boxes + 3 strips, exact totals ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sale-checkout-1-abc12345",
            "items": [
                {"pharmacy_product_id": product_id, "sale_unit": "box", "quantity": 2,
                 "expected_unit_price_piastres": 10500, "expected_line_total_piastres": 21000},
                {"pharmacy_product_id": product_id, "sale_unit": "strip", "quantity": 3,
                 "expected_unit_price_piastres": 1750, "expected_line_total_piastres": 5250},
            ],
        }, timeout=15)
        print(f"  sale -> {r.status_code}")
        check("sale 201", r.status_code, 201)
        check("total = 21000+5250 = 26250", r.json()["data"]["total_amount_piastres"], 26250)
        sale1 = r.json()["data"]["sale_id"]

        qc.execute("SELECT total_amount FROM sales WHERE id=%s", (sale1,))
        check("DB sales.total_amount = 26250", qc.fetchone()[0], 26250)
        qc.execute("SELECT amount_piastres, base_quantity, cost_amount_piastres FROM sale_items s "
                   "JOIN sales sl ON sl.id=s.sale_id WHERE sl.id=%s ORDER BY s.unit_price DESC", (sale1,))
        rows = qc.fetchall()
        # unit cost per strip = 10550/6 = 1758.33 -> documented half-up = 1758
        check("box row: amount 21000, strips 12, cost 12*1758=21096",
              (rows[0][0], int(rows[0][1]), rows[0][2]), (21000, 12, 21096))
        check("strip row: amount 5250, strips 3, cost 3*1758=5274",
              (rows[1][0], int(rows[1][1]), rows[1][2]), (5250, 3, 5274))
        qc.execute("SELECT ROUND(quantity)::bigint FROM inventory_batches WHERE pharmacy_product_id=%s", (product_id,))
        check("stock drained to 0", qc.fetchone()[0], 0)
        qc.execute("SELECT COUNT(*) FROM sales")
        check("exactly 1 sale stored", qc.fetchone()[0], 1)

        print("== idempotent replay of the same checkout ==")
        r2 = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sale-checkout-1-abc12345",
            "items": [
                {"pharmacy_product_id": product_id, "sale_unit": "box", "quantity": 2,
                 "expected_unit_price_piastres": 10500, "expected_line_total_piastres": 21000},
                {"pharmacy_product_id": product_id, "sale_unit": "strip", "quantity": 3,
                 "expected_unit_price_piastres": 1750, "expected_line_total_piastres": 5250},
            ],
        }, timeout=15)
        check("replay 200", r2.status_code, 200)
        check("replayed flag", r2.json()["data"]["replayed"], True)
        check("same sale id", r2.json()["data"]["sale_id"], sale1)
        qc.execute("SELECT COUNT(*) FROM sales")
        check("still exactly 1 sale", qc.fetchone()[0], 1)

        print("== product 2 with non-divisible prices (box 10700, strip 1783, 1783*6=10698 != 10700) ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "بروفين", "generic_name": "Ibuprofen", "dosage_form": "tablet",
            "strength": "400mg", "barcode": "9900002", "packaging_type": "BOX_STRIP",
            "units_per_box": 6,
            "cost_price_piastres": 9000, "selling_price_piastres": 10700,
            "partial_selling_price_piastres": 1783,
            "min_stock_level": 0, "initial_boxes": 0, "initial_strips": 12,
            "batch_number": "B-MAIN", "expiry_date": "2027-01-01",
        }, timeout=10)
        check("product 2 created", r.status_code, 201)
        product2 = r.json()["data"]["id"]
        # cost per strip = 9000/6 = 1500 exact

        print("== split product 2 batch into 5 + 7 strips ==")
        qc.execute("UPDATE inventory_batches SET quantity=5 WHERE pharmacy_product_id=%s", (product2,))
        qc.execute("SELECT id FROM company_users WHERE email=%s", (email,))
        actor = qc.fetchone()[0]
        qc.execute(
            "INSERT INTO inventory_batches (pharmacy_product_id, branch_id, batch_number, quantity, unit, cost_per_unit, received_by, reference_type) "
            "SELECT pharmacy_product_id, branch_id, 'B-SPLIT', 7, 'strip'::unit_type, 1500, NULL, 'opening_balance' "
            "FROM inventory_batches WHERE pharmacy_product_id=%s", (product2,))
        qc.execute(
            "INSERT INTO stock_movements (batch_id, movement_type, quantity, unit, quantity_before, quantity_after, unit_cost, total_cost, created_by_company_user_id, reason) "
            "SELECT b.id, 'purchase'::movement_type, b.quantity, b.unit, 0, b.quantity, 1500, (b.quantity*1500)::numeric, %s, 'test' "
            "FROM inventory_batches b WHERE b.pharmacy_product_id=%s", (actor, product2))

        print("== sale A (no intent): 3 strips at authoritative price ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sale-a-no-intent-abc12345",
            "items": [
                {"pharmacy_product_id": product2, "sale_unit": "strip", "quantity": 3},
            ],
        }, timeout=15)
        check("no-intent sale 201", r.status_code, 201)
        check("3 strips at 1783 = 5349", r.json()["data"]["total_amount_piastres"], 5349)
        # MAIN batch: 5 -> 2 strips

        print("== sale B (fragmented box): 1 box over batches [2,4] with piastre remainder ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sale-b-fragmented-abc12345",
            "items": [
                {"pharmacy_product_id": product2, "sale_unit": "box", "quantity": 1,
                 "expected_unit_price_piastres": 10700, "expected_line_total_piastres": 10700},
            ],
        }, timeout=15)
        check("fragmented sale 201", r.status_code, 201)
        sale_b = r.json()["data"]["sale_id"]
        check("line total exact 10700", r.json()["data"]["total_amount_piastres"], 10700)
        qc.execute("SELECT amount_piastres FROM sale_items WHERE sale_id=%s ORDER BY amount_piastres", (sale_b,))
        amounts = sorted(row[0] for row in qc.fetchall())
        # 10700 over 2/6 and 4/6 strips: floors 3566+7133=10699, +1 to larger remainder (2 strips row)
        check("allocation [3567, 7133] sums exactly to 10700", amounts, [3567, 7133])

        print("== idempotent replay of fragmented sale ==")
        r2 = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "sale-b-fragmented-abc12345",
            "items": [
                {"pharmacy_product_id": product2, "sale_unit": "box", "quantity": 1,
                 "expected_unit_price_piastres": 10700, "expected_line_total_piastres": 10700},
            ],
        }, timeout=15)
        check("fragmented replay 200 replayed", r2.status_code == 200 and r2.json()["data"]["replayed"], True)

        print("== stale price intent -> 409 price_changed with authoritative prices ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "items": [
                {"pharmacy_product_id": product2, "sale_unit": "strip", "quantity": 2,
                 "expected_unit_price_piastres": 9999, "expected_line_total_piastres": 19998},
            ],
        }, timeout=15)
        check("price mismatch 409", r.status_code, 409)
        body = r.json()
        check("error code", body.get("error"), "price_changed")
        item = body["data"]["items"][0]
        check("authoritative strip price returned", item["unit_price_piastres"], 1783)
        check("authoritative line total returned", item["line_total_piastres"], 3566)

        print("== insufficient stock -> 409 ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "items": [
                {"pharmacy_product_id": product2, "sale_unit": "box", "quantity": 999},
            ],
        }, timeout=15)
        check("insufficient stock 409", r.status_code, 409)
        check("error code", r.json().get("error"), "insufficient_stock")

        print("== dashboard inventory exposes *_piastres integers ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "أوجنتين", "generic_name": "Mefenamic", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9900004", "packaging_type": "WHOLE_ONLY",
            "units_per_box": 1,
            "cost_price_piastres": 1000, "selling_price_piastres": 2500,
            "partial_selling_price_piastres": None,
            "min_stock_level": 0, "initial_boxes": 10, "initial_strips": 0,
        }, timeout=10)
        check("product 3 created", r.status_code, 201)
        r = s.get(f"{BASE}/pharmacy/inventory", timeout=10)
        check("inventory 200", r.status_code, 200)
        items = r.json()["data"]
        p3 = next(i for i in items if i["barcode"] == "9900004")
        check("selling_price_piastres key", p3["selling_price_piastres"], 2500)
        check("cost_per_unit_piastres key", p3["cost_per_unit_piastres"], 1000)
        check("total_cost_piastres generated = 10*1000", p3["total_cost_piastres"], 10000)
        check("quantity integer", p3["quantity"], 10)

        print("== missing partial price rejected for BOX_STRIP ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "بدون سعر شريط", "dosage_form": "tablet", "barcode": "9900003",
            "packaging_type": "BOX_STRIP", "units_per_box": 4,
            "cost_price_piastres": 1000, "selling_price_piastres": 2000,
            "partial_selling_price_piastres": None,
            "min_stock_level": 0, "initial_boxes": 0, "initial_strips": 0,
        }, timeout=10)
        check("partial price required 400", r.status_code, 400)
        check("error code", r.json().get("error"), "partial_price_required")

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
    print("\nRESULT: ALL MONEY API CHECKS PASSED")


if __name__ == "__main__":
    main()
