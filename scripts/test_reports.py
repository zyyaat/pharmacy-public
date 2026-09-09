#!/usr/bin/env python3
"""Layer B: reports module (التقارير) — Task 27.

Fresh database -> migrations on startup -> real server.

Scenario built through REAL flows only:
  * product create (6 products incl. low-stock + zeroed + near-expiry batches)
  * POS sales (box + strips) and a partial customer return
  * adjustments +7 / -2 / -3 (zeroing product D)

Covers:
  * GET /pharmacy/reports/sales?from&to   KPIs (gross/returned/net/units/avg),
    daily series, top products, period defaults and validation
  * GET /pharmacy/reports/inventory       valuation (cost + retail honoring
    strip pricing), low/out counts, expiry buckets, watchlists (+extra_date)
  * GET /pharmacy/reports/movements       by-type aggregates + totals
  * GET /pharmacy/pos/sales?from&to       invoice date filter
  * auth guard 401 + validation 400s
"""
import os
import subprocess
import sys
import time
import uuid
from datetime import date, timedelta

import psycopg2
import requests

ROOT = os.path.join(os.path.dirname(__file__), "..")
GO = os.environ.get("GO_BIN", "/tmp/go/bin/go")
SERVER_PORT = 18097
BASE = f"http://127.0.0.1:{SERVER_PORT}/api/v1"
ADMIN_DSN = "postgresql://postgres@127.0.0.1:54329/postgres"
TEST_DB = "reports_test"
SERVER_DSN = f"postgresql://postgres@127.0.0.1:54329/{TEST_DB}"

FAILURES = []


def check(name, got, want):
    ok = got == want
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: got={got!r} want={want!r}")
    if not ok:
        FAILURES.append(name)


def main():
    admin = psycopg2.connect(ADMIN_DSN)
    admin.autocommit = True
    cur = admin.cursor()
    cur.execute(f"DROP DATABASE IF EXISTS {TEST_DB}")
    cur.execute(f"CREATE DATABASE {TEST_DB}")

    conn = None
    server = None
    try:
        print("== building server ==")
        subprocess.run([GO, "build", "-o", "/tmp/reports_server", "./cmd/server"],
                       cwd=os.path.join(ROOT, "backend"), check=True)

        print("== starting server on fresh DB ==")
        env = dict(os.environ, DATABASE_URL=SERVER_DSN, PORT=str(SERVER_PORT), APP_ENV="development")
        server = subprocess.Popen(["/tmp/reports_server"], env=env,
                                  stdout=open("/tmp/reports_server.log", "w"),
                                  stderr=subprocess.STDOUT)
        for _ in range(60):
            try:
                if requests.get(f"{BASE}/health", timeout=1).status_code == 200:
                    break
            except requests.RequestException:
                time.sleep(0.5)
        else:
            raise SystemExit("server did not become healthy")
        print("  server healthy")

        # ---- auth ----
        s = requests.Session()
        email = f"rep-{uuid.uuid4().hex[:8]}@test.io"
        password = "Str0ng!Pass2026"
        s.post(f"{BASE}/auth/register", json={
            "company_name": "Reports Co", "company_email": email,
            "first_name": "عامر", "last_name": "الصيدلي",
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

        # ---- guard: no session ----
        print("== auth guard ==")
        check("sales report 401", requests.get(f"{BASE}/pharmacy/reports/sales", timeout=5).status_code, 401)
        check("inventory report 401", requests.get(f"{BASE}/pharmacy/reports/inventory", timeout=5).status_code, 401)
        check("movements report 401", requests.get(f"{BASE}/pharmacy/reports/movements", timeout=5).status_code, 401)

        # ---- scenario products ----
        print("== products (A,B sellables; C low; D to-zero; E near-expiry; F expired) ==")
        def create_product(payload):
            return s.post(f"{BASE}/pharmacy/products", headers=headers, json=payload, timeout=10)

        r = create_product({
            "name": "بانادول أدفانس", "generic_name": "Paracetamol", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9800410", "packaging_type": "BOX_STRIP",
            "units_per_box": 5,
            "cost_price_piastres": 8000, "selling_price_piastres": 10000,
            "partial_selling_price_piastres": 2000,
            "min_stock_level": 0, "initial_boxes": 2, "initial_strips": 1,
            "batch_number": "RP-A", "expiry_date": "2027-06-01",
        })
        check("product A created", r.status_code, 201)
        pid_a = r.json()["data"]["id"]

        r = create_product({
            "name": "كونجستال", "generic_name": "Paracetamol", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9800411", "packaging_type": "WHOLE_ONLY",
            "units_per_box": 1,
            "cost_price_piastres": 1500, "selling_price_piastres": 2000,
            "partial_selling_price_piastres": None,
            "min_stock_level": 0, "initial_boxes": 4, "initial_strips": 0,
            "batch_number": "RP-B", "expiry_date": "2027-08-01",
        })
        check("product B created", r.status_code, 201)

        r = create_product({
            "name": "فيتامين سي", "generic_name": "Ascorbic Acid", "dosage_form": "tablet",
            "strength": "1000mg", "barcode": "9800412", "packaging_type": "WHOLE_ONLY",
            "units_per_box": 1,
            "cost_price_piastres": 1000, "selling_price_piastres": 2500,
            "partial_selling_price_piastres": None,
            "min_stock_level": 10, "initial_boxes": 2, "initial_strips": 0,
            "batch_number": "RP-C", "expiry_date": "2027-01-01",
        })
        check("product C (low stock) created", r.status_code, 201)

        r = create_product({
            "name": "شربة ساخنة", "generic_name": "", "dosage_form": "syrup",
            "strength": "", "barcode": "9800413", "packaging_type": "WHOLE_ONLY",
            "units_per_box": 1,
            "cost_price_piastres": 500, "selling_price_piastres": 700,
            "partial_selling_price_piastres": None,
            "min_stock_level": 0, "initial_boxes": 3, "initial_strips": 0,
            "batch_number": "RP-D", "expiry_date": "2027-01-01",
        })
        check("product D created", r.status_code, 201)
        pid_d = r.json()["data"]["id"]

        r = create_product({
            "name": "شراب كحة", "generic_name": "", "dosage_form": "syrup",
            "strength": "", "barcode": "9800414", "packaging_type": "WHOLE_ONLY",
            "units_per_box": 1,
            "cost_price_piastres": 300, "selling_price_piastres": 900,
            "partial_selling_price_piastres": None,
            "min_stock_level": 0, "initial_boxes": 5, "initial_strips": 0,
            "batch_number": "RP-E", "expiry_date": "2027-01-01",
        })
        check("product E created", r.status_code, 201)

        r = create_product({
            "name": "مرهم جروح", "generic_name": "", "dosage_form": "cream",
            "strength": "", "barcode": "9800415", "packaging_type": "WHOLE_ONLY",
            "units_per_box": 1,
            "cost_price_piastres": 400, "selling_price_piastres": 700,
            "partial_selling_price_piastres": None,
            "min_stock_level": 0, "initial_boxes": 6, "initial_strips": 0,
            "batch_number": "RP-F", "expiry_date": "2027-01-01",
        })
        check("product F created", r.status_code, 201)

        # backdate expiry for E (+20d) and F (yesterday)
        c3 = psycopg2.connect(SERVER_DSN)
        c3.autocommit = True
        cc = c3.cursor()
        cc.execute("UPDATE inventory_batches SET expiry_date = CURRENT_DATE + 20 WHERE batch_number = 'RP-E'")
        cc.execute("UPDATE inventory_batches SET expiry_date = CURRENT_DATE - 1 WHERE batch_number = 'RP-F'")
        c3.close()

        # ---- sales: 1 box (10000) then 3 strips (6000) ----
        print("== POS sale 1: 1 box of A ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "rep-sale-1-aaaaaaaa",
            "items": [{"pharmacy_product_id": pid_a, "sale_unit": "box", "quantity": 1}],
        }, timeout=15)
        check("sale 1 created", r.status_code, 201)
        sale1_id = r.json()["data"]["sale_id"]

        print("== POS sale 2: 3 strips of A ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "rep-sale-2-bbbbbbbb",
            "items": [{"pharmacy_product_id": pid_a, "sale_unit": "strip", "quantity": 3}],
        }, timeout=15)
        check("sale 2 created", r.status_code, 201)

        print("== partial return: 2 strips back from sale 1 (4000) ==")
        r = s.get(f"{BASE}/pharmacy/pos/sales/{sale1_id}", timeout=10)
        check("sale detail ok", r.status_code, 200)
        sale_item_id = r.json()["data"]["items"][0]["sale_item_id"]
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale1_id}/returns", headers={
            **headers, "Idempotency-Key": "rep-ret-1-cccccccc",
        }, json={"items": [{"sale_item_id": sale_item_id, "quantity": 2}],
                 "reason": "تلف بالنقل"}, timeout=15)
        check("return created", r.status_code, 201)

        print("== adjustments: +7, -2 on A ; -3 to zero D ==")
        r = s.get(f"{BASE}/pharmacy/inventory", timeout=10)
        rows = {row["batch_number"]: row for row in r.json()["data"]}
        batch_a = rows["RP-A"]["batch_id"]
        batch_d = rows["RP-D"]["batch_id"]
        r = s.post(f"{BASE}/pharmacy/inventory/{batch_a}/adjust", headers={
            **headers, "Idempotency-Key": "rep-adj-1-dddddddd",
        }, json={"delta": 7, "reason": "استلام توريد إضافي"}, timeout=10)
        check("adjust +7 ok", r.status_code, 200)
        r = s.post(f"{BASE}/pharmacy/inventory/{batch_a}/adjust", headers={
            **headers, "Idempotency-Key": "rep-adj-2-eeeeeeee",
        }, json={"delta": -2, "reason": "كسر أثناء الجرد"}, timeout=10)
        check("adjust -2 ok", r.status_code, 200)
        r = s.post(f"{BASE}/pharmacy/inventory/{batch_d}/adjust", headers={
            **headers, "Idempotency-Key": "rep-adj-3-ffffffff",
        }, json={"delta": -3, "reason": "تصفية صنف"}, timeout=10)
        check("adjust -3 (zero D) ok", r.status_code, 200)

        # ================= SALES REPORT =================
        today = date.today().isoformat()
        print("== sales report: today ==")
        r = s.get(f"{BASE}/pharmacy/reports/sales?from={today}&to={today}", timeout=10)
        check("sales report 200", r.status_code, 200)
        rep = r.json()["data"]
        check("period echoed", rep["period"], {"from": today, "to": today})
        check("invoices_count 2", rep["sales"]["invoices_count"], 2)
        check("gross 16000", rep["sales"]["gross_piastres"], 16000)
        check("returns_count 1", rep["sales"]["returns_count"], 1)
        check("returned 4000", rep["sales"]["returned_piastres"], 4000)
        check("net 12000", rep["sales"]["net_piastres"], 12000)
        check("units_base 8", rep["sales"]["units_base"], 8)
        check("avg 8000", rep["sales"]["avg_invoice_piastres"], 8000)
        check("daily rows 1", len(rep["daily"]), 1)
        check("daily net 12000", rep["daily"][0]["net_piastres"], 12000)
        check("daily invoices 2", rep["daily"][0]["invoices_count"], 2)
        check("top products 1", len(rep["top_products"]), 1)
        tp = rep["top_products"][0]
        check("top product name", tp["name"], "بانادول أدفانس")
        check("top product qty 8", tp["quantity_base"], 8)
        check("top product amount 16000", tp["amount_piastres"], 16000)

        print("== sales report: default range (last 30d includes today) ==")
        r = s.get(f"{BASE}/pharmacy/reports/sales", timeout=10)
        rep2 = r.json()["data"]
        check("default invoices 2", rep2["sales"]["invoices_count"], 2)
        check("default daily rows 30", len(rep2["daily"]), 30)

        print("== sales report: validation ==")
        r = s.get(f"{BASE}/pharmacy/reports/sales?from=not-a-date", timeout=10)
        check("bad from 400", r.status_code, 400)
        r = s.get(f"{BASE}/pharmacy/reports/sales?from={today}&to=2020-01-01", timeout=10)
        check("to<from 400", r.status_code, 400)
        r = s.get(f"{BASE}/pharmacy/reports/sales?from=2024-01-01&to=2026-01-01", timeout=10)
        check("range>366d 400", r.status_code, 400)

        # ================= INVENTORY REPORT =================
        print("== inventory report ==")
        r = s.get(f"{BASE}/pharmacy/reports/inventory", timeout=10)
        check("inventory report 200", r.status_code, 200)
        inv = r.json()["data"]
        t = inv["totals"]
        # cost: batches store cost per BASE unit (8000/box ÷ 5 strips = 1600/strip):
        # A 10*1600 + B 4*1500 + C 2*1000 + D 0 + E 5*300 + F 6*400 = 27900
        check("cost value 27900", t["cost_value_piastres"], 27900)
        # retail: A 10*2000(strip) + B 4*2000 + C 2*2500 + D 0 + E 5*900 + F 6*700 = 41700
        check("retail value 41700", t["retail_value_piastres"], 41700)
        check("batches 6", t["batches_count"], 6)
        check("products 6", t["products_count"], 6)
        check("units base 27", t["units_base"], 27)  # 10+4+2+0+5+6
        check("low stock 1 (C)", t["low_stock_count"], 1)
        check("out of stock 1 (D)", t["out_of_stock_count"], 1)
        e = inv["expiry"]
        check("expired 1 (F)", e["expired_count"], 1)
        check("expiring30 1 (E)", e["expiring_30_count"], 1)
        check("expiring60 0", e["expiring_60_count"], 0)
        check("expiring90 0", e["expiring_90_count"], 0)
        check("expired value 2400", e["expired_value_piastres"], 2400)
        check("expiring value 1500", e["expiring_value_piastres"], 1500)
        check("low items 1", len(inv["low_stock_items"]), 1)
        check("low item name", inv["low_stock_items"][0]["name"], "فيتامين سي")
        check("low item qty 2", inv["low_stock_items"][0]["quantity"], 2)
        check("low item threshold 10", inv["low_stock_items"][0]["threshold"], 10)
        check("expiring items 2", len(inv["expiring_items"]), 2)
        check("expired first (order by expiry)", inv["expiring_items"][0]["name"], "مرهم جروح")
        check("expired threshold <= 0", inv["expiring_items"][0]["threshold"] <= 0, True)
        check("near-expiry threshold 20", inv["expiring_items"][1]["threshold"], 20)
        check("expiring extra_date set", inv["expiring_items"][0]["extra_date"] is not None, True)
        check("low item extra_date null", inv["low_stock_items"][0]["extra_date"] is None, True)

        # ================= MOVEMENTS REPORT =================
        print("== movements report ==")
        r = s.get(f"{BASE}/pharmacy/reports/movements?from={today}&to={today}", timeout=10)
        check("movements report 200", r.status_code, 200)
        mov = r.json()["data"]
        by_type = {row["movement_type"]: row for row in mov["by_type"]}
        check("purchase transactions 6", by_type["purchase"]["transactions"], 6)
        check("purchase in 31", by_type["purchase"]["quantity_in"], 31)  # 11+4+2+3+5+6
        check("sale transactions 2", by_type["sale"]["transactions"], 2)
        check("sale out 8", by_type["sale"]["quantity_out"], 8)
        check("return in 2", by_type["return_from_customer"]["quantity_in"], 2)
        check("adjustment transactions 3", by_type["adjustment"]["transactions"], 3)
        check("adjustment in 7", by_type["adjustment"]["quantity_in"], 7)
        check("adjustment out 5", by_type["adjustment"]["quantity_out"], 5)  # 2+3
        tt = mov["totals"]
        check("totals transactions 12", tt["transactions"], 12)
        check("totals in 40", tt["quantity_in"], 40)  # 31+2+7
        check("totals out 13", tt["quantity_out"], 13)  # 8+5
        check("movements validation 400", s.get(
            f"{BASE}/pharmacy/reports/movements?from=xx", timeout=10).status_code, 400)

        # ================= POS SALES DATE FILTER =================
        print("== pos/sales from/to ==")
        r = s.get(f"{BASE}/pharmacy/pos/sales?from={today}", timeout=10)
        check("sales today total 2", r.json()["data"]["total"], 2)
        yesterday = (date.today() - timedelta(days=1)).isoformat()
        r = s.get(f"{BASE}/pharmacy/pos/sales?to={yesterday}", timeout=10)
        check("sales until yesterday 0", r.json()["data"]["total"], 0)
        r = s.get(f"{BASE}/pharmacy/pos/sales?from=bad-date", timeout=10)
        check("sales bad from 400", r.status_code, 400)

        # ---- summary ----
        print()
        if FAILURES:
            print(f"RESULT: {len(FAILURES)} FAILURES -> {FAILURES}")
            sys.exit(1)
        print("RESULT: ALL PASS")
    finally:
        if server:
            server.terminate()
            try:
                server.wait(timeout=10)
            except Exception:
                server.kill()
        if conn:
            conn.close()


if __name__ == "__main__":
    main()
