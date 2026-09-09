#!/usr/bin/env python3
"""Layer B: inventory movements log (سجل حركات المخزون) — Task 26.

Fresh database -> migrations (01..17) on startup -> real server.

Scenario built through REAL flows only:
  * product create            -> purchase movement (opening_balance)
  * POS sale                  -> sale movement (negative, reference sale)
  * POS return (credit note)  -> return_from_customer movement (positive)
  * adjust + / -              -> adjustment movements

Covers:
  * GET /pharmacy/inventory/movements: totals, DESC order, rich fields
    (product, batch, actor, quantity_after, reference)
  * filters: type (each), search (product name / batch number),
    direction in/out, from/to date range (inclusive `to`), pagination
  * validation: unknown type 400, bad direction 400, bad dates 400
  * auth guard: no session -> 401
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
SERVER_PORT = 18096
BASE = f"http://127.0.0.1:{SERVER_PORT}/api/v1"
ADMIN_DSN = "postgresql://postgres@127.0.0.1:54329/postgres"
TEST_DB = "movements_test"
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
        subprocess.run([GO, "build", "-o", "/tmp/movements_server", "./cmd/server"],
                       cwd=os.path.join(ROOT, "backend"), check=True)

        print("== starting server on fresh DB ==")
        env = dict(os.environ, DATABASE_URL=SERVER_DSN, PORT=str(SERVER_PORT), APP_ENV="development")
        server = subprocess.Popen(["/tmp/movements_server"], env=env,
                                  stdout=open("/tmp/movements_server.log", "w"),
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

        s = requests.Session()
        email = f"mov-{uuid.uuid4().hex[:8]}@test.io"
        password = "Str0ng!Pass2026"
        s.post(f"{BASE}/auth/register", json={
            "company_name": "Movements Co", "company_email": email,
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

        # ---- scenario: build movements through real flows ----
        print("== product A (BOX_STRIP, upb 5, 2 boxes + 1 strip) -> purchase movement ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "بانادول أدفانس", "generic_name": "Paracetamol", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9800310", "packaging_type": "BOX_STRIP",
            "units_per_box": 5,
            "cost_price_piastres": 8000, "selling_price_piastres": 10000,
            "partial_selling_price_piastres": 2000,
            "min_stock_level": 0, "initial_boxes": 2, "initial_strips": 1,
            "batch_number": "MV-A", "expiry_date": "2027-06-01",
        }, timeout=10)
        check("product A created", r.status_code, 201)
        pid_a = r.json()["data"]["id"]

        print("== product B (WHOLE_ONLY) -> second purchase movement ==")
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json={
            "name": "كونجستال", "generic_name": "Paracetamol", "dosage_form": "tablet",
            "strength": "500mg", "barcode": "9800311", "packaging_type": "WHOLE_ONLY",
            "units_per_box": 1,
            "cost_price_piastres": 1500, "selling_price_piastres": 2000,
            "partial_selling_price_piastres": None,
            "min_stock_level": 0, "initial_boxes": 4, "initial_strips": 0,
            "batch_number": "MV-B", "expiry_date": "2027-08-01",
        }, timeout=10)
        check("product B created", r.status_code, 201)

        print("== POS sale: 1 box of A -> sale movement -5 ==")
        r = s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
            "idempotency_key": "mov-sale-1-aaaaaaaa",
            "items": [{"pharmacy_product_id": pid_a, "sale_unit": "box", "quantity": 1}],
        }, timeout=15)
        check("sale created", r.status_code, 201)
        sale_id = r.json()["data"]["sale_id"]

        print("== POS return: 5 strips back -> return_from_customer +5 ==")
        r = s.get(f"{BASE}/pharmacy/pos/sales/{sale_id}", timeout=10)
        check("sale detail ok", r.status_code, 200)
        sale_item_id = r.json()["data"]["items"][0]["sale_item_id"]
        r = s.post(f"{BASE}/pharmacy/pos/sales/{sale_id}/returns", headers={
            **headers, "Idempotency-Key": "mov-ret-1-bbbbbbbb",
        }, json={"items": [{"sale_item_id": sale_item_id, "quantity": 5}],
                 "reason": "تلف بالنقل"}, timeout=15)
        check("return created", r.status_code, 201)

        print("== adjustments: +7 then -2 ==")
        r = s.get(f"{BASE}/pharmacy/inventory", timeout=10)
        rows = {row["batch_number"]: row for row in r.json()["data"]}
        batch_a = rows["MV-A"]["batch_id"]
        r = s.post(f"{BASE}/pharmacy/inventory/{batch_a}/adjust", headers={
            **headers, "Idempotency-Key": "mov-adj-1-cccccccc",
        }, json={"delta": 7, "reason": "استلام توريد إضافي"}, timeout=10)
        check("adjust +7 ok", r.status_code, 200)
        r = s.post(f"{BASE}/pharmacy/inventory/{batch_a}/adjust", headers={
            **headers, "Idempotency-Key": "mov-adj-2-dddddddd",
        }, json={"delta": -2, "reason": "كسر أثناء الجرد"}, timeout=10)
        check("adjust -2 ok", r.status_code, 200)

        # expected movements: purchase A, purchase B, sale, return, +7, -2 = 6
        print("== list: no filters ==")
        r = s.get(f"{BASE}/pharmacy/inventory/movements", timeout=10)
        check("list 200", r.status_code, 200)
        data = r.json()["data"]
        check("total 6", data["total"], 6)
        check("rows len 6", len(data["movements"]), 6)
        first = data["movements"][0]
        check("newest first is -2 adjustment", first["movement_type"], "adjustment")
        check("newest quantity -2", first["quantity"], -2)
        check("actor name resolved", first["actor_name"], "عامر الصيدلي")
        check("reason present", first["reason"], "كسر أثناء الجرد")

        by_type = {m["movement_type"]: m for m in data["movements"] if m["movement_type"] in
                   ("sale", "return_from_customer")}
        check("sale row product", by_type["sale"]["product_name"], "بانادول أدفانس")
        check("sale batch", by_type["sale"]["batch_number"], "MV-A")
        check("sale reference", by_type["sale"]["reference_type"], "sale")
        check("sale quantity -5", by_type["sale"]["quantity"], -5)
        check("sale quantity_after 6", by_type["sale"]["quantity_after"], 6)
        check("return quantity +5", by_type["return_from_customer"]["quantity"], 5)
        check("return reference", by_type["return_from_customer"]["reference_type"], "sale_return")

        print("== filter: type ==")
        r = s.get(f"{BASE}/pharmacy/inventory/movements?type=sale", timeout=10)
        check("type=sale total 1", r.json()["data"]["total"], 1)
        r = s.get(f"{BASE}/pharmacy/inventory/movements?type=purchase", timeout=10)
        check("type=purchase total 2", r.json()["data"]["total"], 2)
        check("purchase reason opening", r.json()["data"]["movements"][0]["reason"], "opening_balance")
        r = s.get(f"{BASE}/pharmacy/inventory/movements?type=adjustment", timeout=10)
        check("type=adjustment total 2", r.json()["data"]["total"], 2)
        r = s.get(f"{BASE}/pharmacy/inventory/movements?type=return_from_customer", timeout=10)
        check("type=return_from_customer total 1", r.json()["data"]["total"], 1)

        print("== filter: search ==")
        r = s.get(f"{BASE}/pharmacy/inventory/movements?search=%D8%A8%D8%A7%D9%86%D8%A7%D8%AF%D9%88%D9%84", timeout=10)
        check("search بانادول total 5", r.json()["data"]["total"], 5)
        r = s.get(f"{BASE}/pharmacy/inventory/movements?search=MV-B", timeout=10)
        check("search batch MV-B total 1", r.json()["data"]["total"], 1)
        check("MV-B product", r.json()["data"]["movements"][0]["product_name"], "كونجستال")

        print("== filter: direction ==")
        r = s.get(f"{BASE}/pharmacy/inventory/movements?direction=in", timeout=10)
        ins = r.json()["data"]["movements"]
        check("direction=in total 4", r.json()["data"]["total"], 4)
        check("all in positive", all(m["quantity"] > 0 for m in ins), True)
        r = s.get(f"{BASE}/pharmacy/inventory/movements?direction=out", timeout=10)
        outs = r.json()["data"]["movements"]
        check("direction=out total 2", r.json()["data"]["total"], 2)
        check("all out negative", all(m["quantity"] < 0 for m in outs), True)

        print("== filter: date range ==")
        today = date.today().isoformat()
        tomorrow = (date.today() + timedelta(days=1)).isoformat()
        yesterday = (date.today() - timedelta(days=1)).isoformat()
        r = s.get(f"{BASE}/pharmacy/inventory/movements?from={today}", timeout=10)
        check("from=today total 6", r.json()["data"]["total"], 6)
        r = s.get(f"{BASE}/pharmacy/inventory/movements?from={tomorrow}", timeout=10)
        check("from=tomorrow total 0", r.json()["data"]["total"], 0)
        r = s.get(f"{BASE}/pharmacy/inventory/movements?to={yesterday}", timeout=10)
        check("to=yesterday total 0", r.json()["data"]["total"], 0)
        r = s.get(f"{BASE}/pharmacy/inventory/movements?to={today}&from={yesterday}", timeout=10)
        check("yesterday..today total 6", r.json()["data"]["total"], 6)

        print("== filter: combined type+search ==")
        r = s.get(f"{BASE}/pharmacy/inventory/movements?type=purchase&search=MV-B", timeout=10)
        check("purchase+MV-B total 1", r.json()["data"]["total"], 1)

        print("== pagination ==")
        r = s.get(f"{BASE}/pharmacy/inventory/movements?limit=2&offset=0", timeout=10)
        check("page1 len 2", len(r.json()["data"]["movements"]), 2)
        check("total still 6", r.json()["data"]["total"], 6)
        r2 = s.get(f"{BASE}/pharmacy/inventory/movements?limit=2&offset=4", timeout=10)
        check("page3 len 2", len(r2.json()["data"]["movements"]), 2)
        ids1 = {m["id"] for m in r.json()["data"]["movements"]}
        ids2 = {m["id"] for m in r2.json()["data"]["movements"]}
        check("pages disjoint", len(ids1 & ids2), 0)

        print("== validation ==")
        r = s.get(f"{BASE}/pharmacy/inventory/movements?type=not_a_type", timeout=10)
        check("bad type 400", r.status_code, 400)
        check("bad type code", r.json().get("error"), "invalid_movement_type")
        r = s.get(f"{BASE}/pharmacy/inventory/movements?direction=sideways", timeout=10)
        check("bad direction 400", r.status_code, 400)
        r = s.get(f"{BASE}/pharmacy/inventory/movements?from=31-12-2026", timeout=10)
        check("bad from 400", r.status_code, 400)

        print("== auth guard ==")
        r = requests.get(f"{BASE}/pharmacy/inventory/movements", timeout=10)
        check("anonymous 401", r.status_code, 401)

    finally:
        if server:
            server.send_signal(9)
            server.wait(timeout=10)
        try:
            admin.cursor().execute(f"DROP DATABASE IF EXISTS {TEST_DB}")
        except Exception:
            pass

    print()
    if FAILURES:
        print(f"RESULT: {len(FAILURES)} FAILURES -> {FAILURES}")
        sys.exit(1)
    print("RESULT: ALL PASS")


if __name__ == "__main__":
    main()
