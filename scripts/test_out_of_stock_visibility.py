#!/usr/bin/env python3
"""Layer B: out-of-stock products must stay visible (migration 16).

Fresh database -> migrations (01..16) on startup -> real server.

Regression for the live-reported bug: selling the last unit of a batch
used to drop the row from current_inventory (the old view filtered
quantity > 0), so the product vanished from the inventory screen.
After this suite the sold-out batch must:
  * still appear in GET /pharmacy/inventory with quantity 0
  * carry status 'out_of_stock'
  * count toward the dashboard low-stock list (reorder semantics)
  * remain sellable-lookup-able in POS with stock = 0
  * accept a restock adjustment and a credit-note return, both of which
    flip the status back to a live state
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
SERVER_PORT = 18098
BASE = f"http://127.0.0.1:{SERVER_PORT}/api/v1"
DSN = "postgresql://postgres@127.0.0.1:54329/postgres"
TEST_DB = "oos_visibility_test"
SERVER_DSN = f"postgresql://postgres@127.0.0.1:54329/{TEST_DB}"

FAILURES = []


def check(name, got, want):
    ok = got == want
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: got={got!r} want={want!r}")
    if not ok:
        FAILURES.append(name)


def inv_rows(s):
    r = s.get(f"{BASE}/pharmacy/inventory", timeout=10)
    assert r.status_code == 200, r.text
    return {row["batch_number"]: row for row in r.json()["data"]}


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
        subprocess.run([GO, "build", "-o", "/tmp/oos_server", "./cmd/server"],
                       cwd=os.path.join(ROOT, "backend"), check=True)

        print("== starting server on fresh DB ==")
        env = dict(os.environ, DATABASE_URL=SERVER_DSN, PORT=str(SERVER_PORT), APP_ENV="development")
        server = subprocess.Popen(["/tmp/oos_server"], env=env,
                                  stdout=open("/tmp/oos_server.log", "w"),
                                  stderr=subprocess.STDOUT)
        for _ in range(60):
            try:
                if requests.get(f"{BASE}/health", timeout=1).status_code == 200:
                    break
            except requests.RequestException:
                time.sleep(0.5)
        else:
            raise SystemExit("server did not become healthy")
        print("  server healthy (migrations 01..16 applied on startup)")

        s = requests.Session()
        email = f"oos-{uuid.uuid4().hex[:8]}@test.io"
        password = "Str0ng!Pass2026"
        r = s.post(f"{BASE}/auth/register", json={
            "company_name": "OOS Test Co", "company_email": email,
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

        # ------------------------------------------------------------------
        print("== products: PANADOL (5/box, 2 boxes, min 0) + CONGESTAL (min 3, 2 strips) ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "بانادول", "generic_name": "Paracetamol", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9800016", "packaging_type": "BOX_STRIP",
            "units_per_box": 5,
            "cost_price_piastres": 8000, "selling_price_piastres": 10000,
            "partial_selling_price_piastres": 2200,
            "min_stock_level": 0, "initial_boxes": 2, "initial_strips": 0,
            "batch_number": "B-OOS", "expiry_date": "2027-06-01",
        }, timeout=10)
        check("panadol created", r.status_code, 201)
        panadol = r.json()["data"]["id"]

        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "كونجستال", "generic_name": "Paracetamol+CPM", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9800017", "packaging_type": "BOX_STRIP",
            "units_per_box": 4,
            "cost_price_piastres": 1500, "selling_price_piastres": 2000,
            "partial_selling_price_piastres": 600,
            "min_stock_level": 3, "initial_boxes": 0, "initial_strips": 2,
            "batch_number": "B-LOW", "expiry_date": "2027-06-01",
        }, timeout=10)
        check("congestal created", r.status_code, 201)

        rows = inv_rows(s)
        check("panadol visible at start", "B-OOS" in rows, True)
        check("panadol quantity 10", int(rows["B-OOS"]["quantity"]), 10)
        check("panadol status normal", rows["B-OOS"]["status"], "normal")
        check("congestal status low_stock", rows["B-LOW"]["status"], "low_stock")

        # ------------------------------------------------------------------
        print("== sell ALL panadol stock (2 boxes) ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "oos-sale-1-aaaaaaaa",
            "items": [{"pharmacy_product_id": panadol, "sale_unit": "box", "quantity": 2}],
        }, timeout=15)
        check("sale 201", r.status_code, 201)
        check("sale total 20000", r.json()["data"]["total_amount_piastres"], 20000)
        sale_id = r.json()["data"]["sale_id"]

        # THE regression: the sold-out product must still be listed.
        rows = inv_rows(s)
        check("panadol STILL visible after full sell", "B-OOS" in rows, True)
        if "B-OOS" in rows:
            check("panadol quantity 0", int(rows["B-OOS"]["quantity"]), 0)
            check("panadol status out_of_stock", rows["B-OOS"]["status"], "out_of_stock")

        print("== POS lookup still answers with stock 0 ==")
        r = s.get(f"{BASE}/pharmacy/pos/products?barcode=9800016", timeout=10)
        check("pos lookup 200", r.status_code, 200)
        check("pos stock 0", r.json()["data"]["stock"], 0)

        print("== selling from an empty batch is rejected ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "oos-sale-2-bbbbbbbb",
            "items": [{"pharmacy_product_id": panadol, "sale_unit": "box", "quantity": 1}],
        }, timeout=15)
        check("oversell 409", r.status_code, 409)

        print("== dashboard counts the sold-out product as needing reorder ==")
        r = s.get(f"{BASE}/pharmacy/dashboard/stats", timeout=10)
        check("stats 200", r.status_code, 200)
        low = {item["name"]: item for item in r.json()["lowStockItems"]}
        check("panadol in lowStockItems", "بانادول" in low, True)
        if "بانادول" in low:
            check("lowStock quantity 0", int(low["بانادول"]["quantity"]), 0)

        print("== restock via inventory adjust (+1 box) ==")
        batch_id = inv_rows(s)["B-OOS"]["batch_id"]
        r = s.post(f"{BASE}/pharmacy/inventory/{batch_id}/adjust", headers={
            **headers, "Idempotency-Key": "oos-adjust-1-cccccccc",
        }, json={"delta": 5, "reason": "إعادة تعبئة بعد النفاذ"}, timeout=10)
        check("adjust 200", r.status_code, 200)
        rows = inv_rows(s)
        check("panadol quantity 5 after restock", int(rows["B-OOS"]["quantity"]), 5)
        check("panadol status normal after restock", rows["B-OOS"]["status"], "normal")

        print("== sell rest down to 0 again, then credit-note return restores it ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "oos-sale-3-dddddddd",
            "items": [{"pharmacy_product_id": panadol, "sale_unit": "box", "quantity": 1}],
        }, timeout=15)
        check("second sale 201", r.status_code, 201)

        rows = inv_rows(s)
        check("panadol sold out again", (int(rows["B-OOS"]["quantity"]), rows["B-OOS"]["status"]), (0, "out_of_stock"))

        r = s.get(f"{BASE}/pharmacy/pos/sales/{sale_id}", timeout=10)
        check("sale detail 200", r.status_code, 200)
        detail = r.json()["data"]
        item = detail["items"][0]
        check("detail returnable 10", int(item["returnable_quantity_base"]), 10)

        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale_id}/returns", headers=headers, json={
            "items": [{"sale_item_id": item["sale_item_id"], "quantity": 5}],
            "reason": "العميل رجع علبة",
        }, timeout=15)
        check("return 201", r.status_code, 201)
        check("return refund 10000", r.json()["data"]["total_amount_piastres"], 10000)

        rows = inv_rows(s)
        check("stock restored to exact batch", int(rows["B-OOS"]["quantity"]), 5)
        check("status live again", rows["B-OOS"]["status"], "normal")

        print("== view definition has no >0 row filter (DB-level proof) ==")
        qc.execute("SELECT pg_get_viewdef('current_inventory'::regclass, true)")
        viewdef = qc.fetchone()[0]
        check("no WHERE filter left in view", "WHERE" in viewdef, False)
        check("out_of_stock branch present", "out_of_stock" in viewdef, True)

        print()
        if FAILURES:
            print(f"FAILED ({len(FAILURES)}): {FAILURES}")
            sys.exit(1)
        print("ALL PASS")
    finally:
        if server is not None:
            server.send_signal(signal.SIGTERM)
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
        if conn is not None:
            conn.close()
        admin.close()


if __name__ == "__main__":
    main()
