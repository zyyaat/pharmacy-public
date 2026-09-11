#!/usr/bin/env python3
"""Seed reports_test with the Task-27 scenario for PRINT verification.

Assumes a server already running on :8080 against a FRESH reports_test DB.
Fixed credentials so the browser can log in:
  print-test@test.io / Str0ng!Pass2026
"""
import os
import sys
import time
import requests

BASE = "http://127.0.0.1:8080/api/v1"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"


def wait_health():
    for _ in range(60):
        try:
            if requests.get(f"{BASE.rsplit('/api', 1)[0]}/health", timeout=1).status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(0.5)
    return False


def main():
    if not wait_health():
        sys.exit("server not healthy on :8080")

    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": "صيدلية الشفاء", "company_email": EMAIL,
        "first_name": "عامر", "last_name": "الصيدلي",
        "email": EMAIL, "password": PASSWORD,
    }, timeout=10)
    print("register:", r.status_code)

    # verify email directly (dev-only flow, same as test_reports.py)
    import psycopg2
    conn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (EMAIL,))
    print("email verified rows:", cur.rowcount)
    # Task 57 — الحساب المزروع حساب قديم «أكمل إعداده»: نغلق بوابة معالج
    # onboarding كي لا يعيد حارس اللوحة توجيه فحوص المتصفح إلى /onboarding.
    cur.execute(
        "UPDATE pharmacies SET settings = settings || '{\"onboarding\": {\"completed\": true}}'::jsonb "
        "WHERE account_id IN (SELECT id FROM accounts WHERE contact_email=%s)",
        (EMAIL,),
    )
    print("onboarding closed rows:", cur.rowcount)
    conn.close()

    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": EMAIL, "password": PASSWORD}, timeout=10)
    print("login:", r.status_code)
    if r.status_code != 200:
        sys.exit("login failed — check email verification step")

    csrf = s.cookies.get("pharmacy_csrf")
    headers = {"X-CSRF-Token": csrf} if csrf else {}

    def create_product(payload):
        r = s.post(f"{BASE}/pharmacy/products", headers=headers, json=payload, timeout=10)
        print("product:", r.status_code, payload["name"])
        return r

    r = create_product({
        "name": "بانادول أدفانس", "generic_name": "Paracetamol", "dosage_form": "tablet",
        "strength": "500mg", "barcode": "9800410", "packaging_type": "BOX_STRIP",
        "units_per_box": 5,
        "cost_price_piastres": 8000, "selling_price_piastres": 10000,
        "partial_selling_price_piastres": 2000,
        "min_stock_level": 0, "initial_boxes": 2, "initial_strips": 1,
        "batch_number": "RP-A", "expiry_date": "2027-06-01",
    })
    pid_a = r.json()["data"]["id"]

    create_product({
        "name": "كونجستال", "generic_name": "Paracetamol", "dosage_form": "tablet",
        "strength": "500mg", "barcode": "9800411", "packaging_type": "WHOLE_ONLY",
        "units_per_box": 1,
        "cost_price_piastres": 1500, "selling_price_piastres": 2000,
        "partial_selling_price_piastres": None,
        "min_stock_level": 0, "initial_boxes": 4, "initial_strips": 0,
        "batch_number": "RP-B", "expiry_date": "2027-08-01",
    })

    create_product({
        "name": "فيتامين سي", "generic_name": "Ascorbic Acid", "dosage_form": "tablet",
        "strength": "1000mg", "barcode": "9800412", "packaging_type": "WHOLE_ONLY",
        "units_per_box": 1,
        "cost_price_piastres": 1000, "selling_price_piastres": 2500,
        "partial_selling_price_piastres": None,
        "min_stock_level": 10, "initial_boxes": 2, "initial_strips": 0,
        "batch_number": "RP-C", "expiry_date": "2027-01-01",
    })

    r = create_product({
        "name": "شربة ساخنة", "generic_name": "", "dosage_form": "syrup",
        "strength": "", "barcode": "9800413", "packaging_type": "WHOLE_ONLY",
        "units_per_box": 1,
        "cost_price_piastres": 500, "selling_price_piastres": 700,
        "partial_selling_price_piastres": None,
        "min_stock_level": 0, "initial_boxes": 3, "initial_strips": 0,
        "batch_number": "RP-D", "expiry_date": "2027-01-01",
    })
    pid_d = r.json()["data"]["id"]

    create_product({
        "name": "شراب كحة", "generic_name": "", "dosage_form": "syrup",
        "strength": "", "barcode": "9800414", "packaging_type": "WHOLE_ONLY",
        "units_per_box": 1,
        "cost_price_piastres": 300, "selling_price_piastres": 900,
        "partial_selling_price_piastres": None,
        "min_stock_level": 0, "initial_boxes": 5, "initial_strips": 0,
        "batch_number": "RP-E", "expiry_date": "2027-01-01",
    })

    create_product({
        "name": "مرهم جروح", "generic_name": "", "dosage_form": "cream",
        "strength": "", "barcode": "9800415", "packaging_type": "WHOLE_ONLY",
        "units_per_box": 1,
        "cost_price_piastres": 400, "selling_price_piastres": 700,
        "partial_selling_price_piastres": None,
        "min_stock_level": 0, "initial_boxes": 6, "initial_strips": 0,
        "batch_number": "RP-F", "expiry_date": "2027-01-01",
    })

    print("sale 1:", s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
        "idempotency_key": "print-sale-1-aaaaaaaa",
        "items": [{"pharmacy_product_id": pid_a, "sale_unit": "box", "quantity": 1}],
    }, timeout=15).status_code)

    print("sale 2:", s.post(f"{BASE}/pharmacy/pos/sales", headers=headers, json={
        "idempotency_key": "print-sale-2-bbbbbbbb",
        "items": [{"pharmacy_product_id": pid_a, "sale_unit": "strip", "quantity": 3}],
    }, timeout=15).status_code)

    sale1_id = s.get(f"{BASE}/pharmacy/pos/sales", timeout=10).json()["data"]["sales"][0]["id"]
    item_id = s.get(f"{BASE}/pharmacy/pos/sales/{sale1_id}", timeout=10).json()["data"]["items"][0]["sale_item_id"]
    print("return:", s.post(f"{BASE}/pharmacy/pos/sales/{sale1_id}/returns", headers={
        **headers, "Idempotency-Key": "print-ret-1-cccccccc",
    }, json={"items": [{"sale_item_id": item_id, "quantity": 2}], "reason": "تلف بالنقل"}, timeout=15).status_code)

    rows = {row["batch_number"]: row for row in s.get(f"{BASE}/pharmacy/inventory", timeout=10).json()["data"]}
    batch_a = rows["RP-A"]["batch_id"]
    batch_d = rows["RP-D"]["batch_id"]
    print("adj +7:", s.post(f"{BASE}/pharmacy/inventory/{batch_a}/adjust", headers={
        **headers, "Idempotency-Key": "print-adj-1-dddddddd",
    }, json={"delta": 7, "reason": "استلام توريد إضافي"}, timeout=10).status_code)
    print("adj -2:", s.post(f"{BASE}/pharmacy/inventory/{batch_a}/adjust", headers={
        **headers, "Idempotency-Key": "print-adj-2-eeeeeeee",
    }, json={"delta": -2, "reason": "كسر أثناء الجرد"}, timeout=10).status_code)
    print("adj -3:", s.post(f"{BASE}/pharmacy/inventory/{batch_d}/adjust", headers={
        **headers, "Idempotency-Key": "print-adj-3-ffffffff",
    }, json={"delta": -3, "reason": "تصفية صنف نهائي"}, timeout=10).status_code)

    print("SEEDED OK — login:", EMAIL, "/", PASSWORD)


if __name__ == "__main__":
    main()
