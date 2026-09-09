#!/usr/bin/env python3
"""Regression: full POS sale checkout still works after search changes."""
import sys

import requests

BASE = "http://127.0.0.1:8080/api/v1"

s = requests.Session()
r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": "print-test@test.io", "password": "Str0ng!Pass2026"}, timeout=10)
assert r.status_code == 200, r.text
csrf = s.cookies.get("pharmacy_csrf")

# pick two products via the NEW search endpoint
r1 = s.get(f"{BASE}/pharmacy/pos/search", params={"q": "كاربيمازول", "limit": 1}, timeout=10)
r2 = s.get(f"{BASE}/pharmacy/pos/search", params={"q": "بانادول", "limit": 1}, timeout=10)
p1, p2 = r1.json()["data"][0], r2.json()["data"][0]
print("picked:", p1["name"], "+", p2["name"])

r = s.post(f"{BASE}/pharmacy/pos/sales", headers={"X-CSRF-Token": csrf}, timeout=15, json={
    "items": [
        {"pharmacy_product_id": p1["id"], "sale_unit": "box", "quantity": 1},
        {"pharmacy_product_id": p2["id"], "sale_unit": "strip", "quantity": 2},
    ],
})
print("checkout:", r.status_code, r.text[:160])
if r.status_code != 201:
    sys.exit(f"FAIL: {r.status_code}")

data = r.json()["data"]
# expected: p1 box 65.00 + p2 2 strips at partial price 35.00 each = 65 + 70 = 135.00 EGP = 13500 piastres
ok = data["total_amount_piastres"] == p1["selling_price_piastres"] + 2 * p2["partial_selling_price_piastres"]
print("total:", data["total_amount_piastres"], "expected:", p1["selling_price_piastres"] + 2 * p2["partial_selling_price_piastres"])
print("REGRESSION", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
