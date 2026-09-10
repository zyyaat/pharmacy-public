#!/usr/bin/env python3
"""بذرة موحّدة idempotent لأصناف بحث POS التي تعتمد عليها اختبارات المتصفح.

تُستدعى من run_receipt_e2e.sh بعد جاهزية الباكند — الإنشاء يتسامح مع 409
(موجود مسبقاً) حتى يمكن تشغيلها قبل أي مجموعة اختبار وبأي ترتيب.
"""
import sys

import requests

BASE = "http://127.0.0.1:8080/api/v1"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"

SEEDS = [
    # (name, generic, barcode)
    ("كاربيمازول 200mg", "كاربيمازين", "6221031500011"),
    ("كاربيمازين CR 400", "كاربيمازين", "6221031500028"),
    ("بانادول اكسترا", "باراسيتامول", "6221004000012"),
    ("كونجستال", "سودوافدرين", "6221048000013"),
    ("أوجمنتين 1g", "أموكسيسيلين/كلافولانيك", "6221031500035"),
]


def main():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": EMAIL, "password": PASSWORD}, timeout=10)
    if r.status_code != 200:
        sys.exit(f"login failed: {r.status_code}")
    csrf = s.cookies.get("pharmacy_csrf")
    hdr = {"X-CSRF-Token": csrf} if csrf else {}

    for name, generic, barcode in SEEDS:
        body = {
            "name": name, "generic_name": generic, "dosage_form": "tablet",
            "strength": "500mg", "barcode": barcode, "packaging_type": "BOX_STRIP",
            "units_per_box": 2, "cost_price_piastres": 4000,
            "selling_price_piastres": 6500, "partial_selling_price_piastres": 3500,
            "min_stock_level": 2, "initial_boxes": 5, "initial_strips": 3,
            "batch_number": f"B-{barcode[-4:]}",
        }
        r = s.post(f"{BASE}/pharmacy/products", headers=hdr, json=body, timeout=10)
        status = "موجود" if r.status_code == 409 else ("أُنشئ" if r.status_code == 201 else f"خطأ {r.status_code}")
        print(f"  [SEED] {name}: {status}")
        if r.status_code not in (200, 201, 409):
            sys.exit(1)
    print("seed fixtures ready")


if __name__ == "__main__":
    main()
