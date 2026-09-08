#!/usr/bin/env python3
"""Layer B: product edit + stock control (Task 24).

Fresh database -> migrations (01..16) on startup -> real server.

Covers:
  * GET  /pharmacy/products/:id    - real stored values for the edit form
  * PUT  /pharmacy/products/:id    - catalog + pricing edits (integer piastres)
  * new prices flow into POS lookup and the NEXT sale total
  * validation parity with creation (negative money, missing strip price,
    units_per_box < 2, empty name)
  * barcode uniqueness across products (409)
  * cross-pharmacy / missing product -> 404
  * is_active toggle hides the product from POS and restores it
  * stock control via /inventory/:batch_id/adjust: +, -, replay idempotency,
    insufficient stock rejection
  * auth + CSRF guards
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
SERVER_PORT = 18097
BASE = f"http://127.0.0.1:{SERVER_PORT}/api/v1"
DSN = "postgresql://postgres@127.0.0.1:54329/postgres"
TEST_DB = "product_edit_test"
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
        subprocess.run([GO, "build", "-o", "/tmp/product_edit_server", "./cmd/server"],
                       cwd=os.path.join(ROOT, "backend"), check=True)

        print("== starting server on fresh DB ==")
        env = dict(os.environ, DATABASE_URL=SERVER_DSN, PORT=str(SERVER_PORT), APP_ENV="development")
        server = subprocess.Popen(["/tmp/product_edit_server"], env=env,
                                  stdout=open("/tmp/product_edit_server.log", "w"),
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
        email = f"edit-{uuid.uuid4().hex[:8]}@test.io"
        password = "Str0ng!Pass2026"
        r = s.post(f"{BASE}/auth/register", json={
            "company_name": "Edit Test Co", "company_email": email,
            "first_name": "Test", "last_name": "User",
            "email": email, "password": password,
        }, timeout=10)
        r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": password}, timeout=10)
        if r.status_code != 200:
            conn = psycopg2.connect(SERVER_DSN)
            conn.autocommit = True
            c2 = conn.cursor()
            c2.execute("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (email,))
            r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": password}, timeout=10)
        check("pharmacy login", r.status_code, 200)
        csrf = s.cookies.get("pharmacy_csrf")
        headers = {"X-CSRF-Token": csrf} if csrf else {}

        if conn is None:
            conn = psycopg2.connect(SERVER_DSN)
        conn.autocommit = True
        qc = conn.cursor()

        print("== create BOX_STRIP product (upb 5, box 10000, strip 2200, 2 boxes) ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "بانادول أدفانس", "generic_name": "Ibuprofen", "dosage_form": "tablet",
            "strength": "400mg", "barcode": "9800020", "packaging_type": "BOX_STRIP",
            "units_per_box": 5,
            "cost_price_piastres": 8000, "selling_price_piastres": 10000,
            "partial_selling_price_piastres": 2200,
            "min_stock_level": 0, "initial_boxes": 2, "initial_strips": 0,
            "batch_number": "B-EDIT", "expiry_date": "2027-06-01",
        }, timeout=10)
        check("product created", r.status_code, 201)
        pid = r.json()["data"]["id"]

        print("== GET product returns the real stored values ==")
        r = s.get(f"{BASE}/pharmacy/products/{pid}", timeout=10)
        check("get 200", r.status_code, 200)
        d = r.json()["data"]
        check("get barcode", d["barcode"], "9800020")
        check("get box price", d["selling_price_piastres"], 10000)
        check("get strip price", d["partial_selling_price_piastres"], 2200)
        check("get cost", d["cost_price_piastres"], 8000)
        check("get is_active", d["is_active"], True)

        print("== PUT edit: rename, reprice, upb 5->4, min stock 3 ==")
        r = s.put(f"{BASE}/pharmacy/products/{pid}", headers=headers, json={
            "name": "بروفين", "generic_name": "Ibuprofen 400", "barcode": "9800999",
            "packaging_type": "BOX_STRIP", "units_per_box": 4,
            "cost_price_piastres": 9000, "selling_price_piastres": 12000,
            "partial_selling_price_piastres": 2600,
            "min_stock_level": 3, "is_active": True,
        }, timeout=10)
        check("put 200", r.status_code, 200)
        d = r.json()["data"]
        check("put echo name", d["name"], "بروفين")
        check("put echo upb", d["units_per_box"], 4)

        r = s.get(f"{BASE}/pharmacy/products/{pid}", timeout=10)
        d = r.json()["data"]
        check("persisted name", d["name"], "بروفين")
        check("persisted barcode", d["barcode"], "9800999")
        check("persisted box price", d["selling_price_piastres"], 12000)
        check("persisted strip price", d["partial_selling_price_piastres"], 2600)
        check("persisted cost", d["cost_price_piastres"], 9000)
        check("persisted min stock", d["min_stock_level"], 3)

        print("== new pricing flows into POS lookup and the NEXT sale ==")
        r = s.get(f"{BASE}/pharmacy/pos/products?barcode=9800999", timeout=10)
        check("pos lookup by new barcode", r.status_code, 200)
        check("pos box price 12000", r.json()["data"]["selling_price_piastres"], 12000)
        check("pos strip price 2600", r.json()["data"]["partial_selling_price_piastres"], 2600)

        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "edit-sale-1-aaaaaaaa",
            "items": [{"pharmacy_product_id": pid, "sale_unit": "box", "quantity": 1}],
        }, timeout=15)
        check("sale with new price 201", r.status_code, 201)
        check("sale total is NEW box price 12000", r.json()["data"]["total_amount_piastres"], 12000)

        print("== validation parity with creation ==")
        base = {
            "name": "بروفين", "generic_name": "Ibuprofen", "barcode": "9800999",
            "packaging_type": "BOX_STRIP", "units_per_box": 4,
            "cost_price_piastres": 9000, "selling_price_piastres": 12000,
            "partial_selling_price_piastres": 2600, "min_stock_level": 3,
        }
        r = s.put(f"{BASE}/pharmacy/products/{pid}", headers=headers,
                  json={**base, "selling_price_piastres": -5}, timeout=10)
        check("negative price 400", r.status_code, 400)
        r = s.put(f"{BASE}/pharmacy/products/{pid}", headers=headers,
                  json={**base, "partial_selling_price_piastres": None}, timeout=10)
        check("missing strip price 400", r.status_code, 400)
        check("missing strip price code", r.json().get("error"), "partial_price_required")
        r = s.put(f"{BASE}/pharmacy/products/{pid}", headers=headers,
                  json={**base, "units_per_box": 1}, timeout=10)
        check("upb 1 for BOX_STRIP 400", r.status_code, 400)
        r = s.put(f"{BASE}/pharmacy/products/{pid}", headers=headers,
                  json={**base, "name": "  "}, timeout=10)
        check("empty name 400", r.status_code, 400)

        print("== barcode uniqueness across products ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "كونجستال", "generic_name": "Paracetamol", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9800021", "packaging_type": "WHOLE_ONLY",
            "units_per_box": 1, "cost_price_piastres": 1500, "selling_price_piastres": 2000,
            "partial_selling_price_piastres": None,
            "min_stock_level": 2, "initial_boxes": 5, "initial_strips": 0,
            "batch_number": "B-C2", "expiry_date": "2027-06-01",
        }, timeout=10)
        check("second product created", r.status_code, 201)
        pid2 = r.json()["data"]["id"]
        r = s.put(f"{BASE}/pharmacy/products/{pid2}", headers=headers,
                  json={
                      "name": "كونجستال", "generic_name": "Paracetamol", "barcode": "9800999",
                      "packaging_type": "WHOLE_ONLY", "units_per_box": 1,
                      "cost_price_piastres": 1500, "selling_price_piastres": 2000,
                      "partial_selling_price_piastres": None, "min_stock_level": 2,
                  }, timeout=10)
        check("conflicting barcode 409", r.status_code, 409)
        check("conflict code", r.json().get("error"), "barcode_already_exists")

        print("== missing / foreign product -> 404 ==")
        ghost = str(uuid.uuid4())
        r = s.get(f"{BASE}/pharmacy/products/{ghost}", timeout=10)
        check("get missing 404", r.status_code, 404)
        r = s.put(f"{BASE}/pharmacy/products/{ghost}", headers=headers,
                  json={**base, "barcode": "9800021"}, timeout=10)
        check("put missing 404", r.status_code, 404)

        print("== is_active toggle hides from POS and restores ==")
        r = s.put(f"{BASE}/pharmacy/products/{pid}", headers=headers,
                  json={**base, "is_active": False}, timeout=10)
        check("deactivate 200", r.status_code, 200)
        check("deactivated flag", r.json()["data"]["is_active"], False)
        r = s.get(f"{BASE}/pharmacy/pos/products?barcode=9800999", timeout=10)
        check("pos lookup now 404", r.status_code, 404)
        r = s.put(f"{BASE}/pharmacy/products/{pid}", headers=headers,
                  json={**base, "is_active": True}, timeout=10)
        check("reactivate 200", r.status_code, 200)
        r = s.get(f"{BASE}/pharmacy/pos/products?barcode=9800999", timeout=10)
        check("pos lookup restored", r.status_code, 200)

        print("== stock control via adjust (movement ledger stays source of truth) ==")
        r = s.get(f"{BASE}/pharmacy/inventory", timeout=10)
        rows = {row["batch_number"]: row for row in r.json()["data"]}
        batch_id = rows["B-EDIT"]["batch_id"]
        sold_check = int(rows["B-EDIT"]["quantity"])  # 10 - 4 (1 box at new upb) = 6
        check("stock after sale is 6", sold_check, 6)

        r = s.post(f"{BASE}/pharmacy/inventory/{batch_id}/adjust", headers={
            **headers, "Idempotency-Key": "edit-adj-1-cccccccc",
        }, json={"delta": 7, "reason": "استلام توريد"}, timeout=10)
        check("adjust +7 -> 200", r.status_code, 200)
        check("adjust new_quantity 13", r.json()["data"]["new_quantity"], 13)

        r = s.post(f"{BASE}/pharmacy/inventory/{batch_id}/adjust", headers={
            **headers, "Idempotency-Key": "edit-adj-1-cccccccc",
        }, json={"delta": 7, "reason": "استلام توريد"}, timeout=10)
        check("replay 200", r.status_code, 200)
        check("replay flagged", r.json()["data"]["replayed"], True)
        check("replay keeps 13", r.json()["data"]["new_quantity"], 13)

        r = s.post(f"{BASE}/pharmacy/inventory/{batch_id}/adjust", headers={
            **headers, "Idempotency-Key": "edit-adj-2-dddddddd",
        }, json={"delta": -2, "reason": "تالف"}, timeout=10)
        check("adjust -2 -> 11", r.json()["data"]["new_quantity"], 11)

        r = s.post(f"{BASE}/pharmacy/inventory/{batch_id}/adjust", headers={
            **headers, "Idempotency-Key": "edit-adj-3-eeeeeeee",
        }, json={"delta": -1000, "reason": "خطأ"}, timeout=10)
        check("over-deduct 409", r.status_code, 409)

        print("== guards: CSRF + anonymous ==")
        r = s.put(f"{BASE}/pharmacy/products/{pid}", json=base, timeout=10)
        check("PUT without CSRF 403", r.status_code, 403)
        r = requests.get(f"{BASE}/pharmacy/products/{pid}", timeout=10)
        check("anonymous GET 401", r.status_code, 401)

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
