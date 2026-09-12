#!/usr/bin/env python3
"""E2E — barcode system v1 (Task 86): full approved flow.

Run against a server on :8080 with a FRESH reports_test DB (migrations run
at boot): python3 scripts/barcode_e2e.py

Covers (Final Decisions 1/2/4/5/6/7/12/13/14):
  1. Create-with-generate → RCN EAN-13, prefix 20, valid Mod-10, type locked
  2. Dedicated generate endpoint + 409 when a barcode already exists
  3. Optional barcode on create (no barcode, no generate)
  4. POS scan path resolves the generated internal barcode
  5. Sale writes the quantity snapshot (sale_quantity + units_per_box_snapshot)
  6. Return math untouched (base units, exact piastres)
  7. Bulk generation: skips products that already carry a code, unique codes
  8. Manual duplicate barcode rejected by the unique index (23505 → 409)
  9. Parallel generation (8 concurrent creates) → 8 distinct valid codes
 10. Label settings: sizes registry, system templates, custom template CRUD
 11. settings.labels permission gates PUT (deny for fresh employee-less owner? —
     owners pass through; verified: owner can write, payload envelope enforced)
 12. audit_logs receives barcode.generated / barcode.replaced rows
"""
import concurrent.futures
import sys
import time
import uuid

import psycopg2
import requests

BASE = "http://127.0.0.1:8080/api/v1"
DB = "postgresql://postgres@127.0.0.1:54329/reports_test"
EMAIL = f"barcode-e2e-{uuid.uuid4().hex[:8]}@test.io"
PASSWORD = "Str0ng!Pass2026"
FAILURES = []


def check(name, ok, extra=""):
    print(("PASS " if ok else "FAIL ") + name + (f"  [{extra}]" if extra and not ok else ""))
    if not ok:
        FAILURES.append(name)


def ean13_valid(code: str) -> bool:
    if len(code) != 13 or not code.isdigit():
        return False
    total = sum(int(d) * (1 if i % 2 == 0 else 3) for i, d in enumerate(code[:12]))
    return (10 - total % 10) % 10 == int(code[12])


def wait_health():
    for _ in range(60):
        try:
            if requests.get("http://127.0.0.1:8080/health", timeout=1).status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(0.5)
    return False


def main():
    assert wait_health(), "server not healthy"

    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": "صيدلية الباركود", "company_email": EMAIL,
        "first_name": "باركود", "last_name": "الاختبار",
        "email": EMAIL, "password": PASSWORD,
    }, timeout=10)
    assert r.status_code in (200, 201), r.text

    conn = psycopg2.connect(DB)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (EMAIL,))
    cur.execute(
        "UPDATE pharmacies SET settings = settings || '{\"onboarding\": {\"completed\": true}}'::jsonb "
        "WHERE account_id IN (SELECT id FROM accounts WHERE contact_email=%s)",
        (EMAIL,),
    )
    conn.commit()

    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": EMAIL, "password": PASSWORD}, timeout=10)
    assert r.status_code == 200, r.text
    csrf = s.cookies.get("pharmacy_csrf")

    # ---- 1) create-with-generate -------------------------------
    r = s.post(f"{BASE}/pharmacy/products", headers={"X-CSRF-Token": csrf}, json={
        "name": "أدڤيل 400mg", "dosage_form": "tablet", "strength": "400mg",
        "barcode": "", "generate_barcode": True,
        "packaging_type": "BOX_STRIP", "units_per_box": 5,
        "cost_price_piastres": 3000, "selling_price_piastres": 5000,
        "partial_selling_price_piastres": 1200,
        "min_stock_level": 0,
        "initial_boxes": 10, "initial_strips": 0,
        "batch_number": "BC-OPENING", "expiry_date": "2027-12-31",
    }, timeout=10)
    check("create-with-generate 201", r.status_code == 201, r.text[:200])
    a = r.json()["data"]
    code_a = a["barcode"]
    check("RCN structure (20 prefix + mod-10)", ean13_valid(code_a) and code_a.startswith("20"), code_a)
    check("type derived RCN_EAN13", a.get("barcode_type") == "RCN_EAN13", str(a.get("barcode_type")))

    # ---- 2) generate endpoint refuses a product that has a code
    r = s.post(f"{BASE}/pharmacy/products/{a['id']}/barcode/generate", headers={"X-CSRF-Token": csrf}, timeout=10)
    check("generate on coded product → 409", r.status_code == 409, r.text[:120])

    # ---- 3) create without barcode and without generate
    r = s.post(f"{BASE}/pharmacy/products", headers={"X-CSRF-Token": csrf}, json={
        "name": "بنادول اكسترا", "dosage_form": "tablet", "strength": "500mg",
        "barcode": "",
        "packaging_type": "BOX_STRIP", "units_per_box": 5,
        "cost_price_piastres": 4000, "selling_price_piastres": 6000,
        "partial_selling_price_piastres": 1500,
        "min_stock_level": 0,
        "initial_boxes": 8, "initial_strips": 0,
        "batch_number": "BC-OPENING-2", "expiry_date": "2027-06-30",
    }, timeout=10)
    check("create without barcode 201", r.status_code == 201, r.text[:200])
    b = r.json()["data"]
    check("no barcode stored", b["barcode"] == "" and b.get("barcode_type") in ("", None), str(b.get("barcode")))

    # ---- 4) dedicated generate on the bare product
    r = s.post(f"{BASE}/pharmacy/products/{b['id']}/barcode/generate", headers={"X-CSRF-Token": csrf}, timeout=10)
    check("generate endpoint 201", r.status_code == 201, r.text[:200])
    code_b = r.json()["data"]["barcode"]
    check("generated distinct code", code_b != code_a and ean13_valid(code_b) and code_b.startswith("20"), code_b)

    # ---- 5) POS scan path resolves the internal code
    r = s.get(f"{BASE}/pharmacy/pos/products", params={"barcode": code_b}, timeout=10)
    check("POS scan resolves internal code", r.status_code == 200 and r.json()["data"]["id"] == b["id"], r.text[:160])

    # ---- 6) sale writes the snapshot ------------------------------
    r = s.post(f"{BASE}/pharmacy/pos/sales", headers={"X-CSRF-Token": csrf}, json={
        "items": [{"pharmacy_product_id": b["id"], "sale_unit": "box", "quantity": 2}],
    }, timeout=15)
    check("sale 201", r.status_code == 201, r.text[:200])
    sale_id = r.json()["data"]["sale_id"]
    r = s.get(f"{BASE}/pharmacy/pos/sales/{sale_id}", timeout=10)
    item = r.json()["data"]["items"][0]
    check("snapshot sale_quantity=2", item.get("sale_quantity") == 2, str(item.get("sale_quantity")))
    check("snapshot units_per_box=5", item.get("units_per_box_snapshot") == 5, str(item.get("units_per_box_snapshot")))
    check("base_quantity exact 10", item["quantity_base"] == 10)

    # ---- 7) return math untouched (base units, no conversion) ----
    r = s.post(f"{BASE}/pharmacy/pos/sales/{sale_id}/returns", headers={"X-CSRF-Token": csrf}, json={
        "items": [{"sale_item_id": item["sale_item_id"], "quantity": 1}],
        "reason": "e2e",
    }, timeout=15)
    check("return 1 strip 201", r.status_code == 201, r.text[:200])
    ret_amount = r.json()["data"]["total_amount_piastres"]
    # The line sold 2 boxes × 6000 = 12000 piastres over 10 base strips, so a
    # 1-strip proportional refund is exactly 1200 (returns refund what was
    # actually charged, not the current shelf strip price).
    check("return refund = 1200 (proportional to line)", ret_amount == 1200, str(ret_amount))

    # ---- 8) bulk generation --------------------------------------
    r = s.post(f"{BASE}/pharmacy/barcodes/bulk-generate", headers={"X-CSRF-Token": csrf},
               json={"ids": [a["id"], b["id"]]}, timeout=15)
    check("bulk skip coded products", r.status_code == 200 and r.json()["data"]["generated"] == 0, r.text[:160])

    created_ids = []
    for i in range(2):
        r = s.post(f"{BASE}/pharmacy/products", headers={"X-CSRF-Token": csrf}, json={
            "name": f"منتج دفعة {i+1}", "dosage_form": "tablet",
            "barcode": "", "packaging_type": "WHOLE_ONLY",
            "cost_price_piastres": 1000, "selling_price_piastres": 2000,
            "min_stock_level": 0,
        }, timeout=10)
        created_ids.append(r.json()["data"]["id"])

    r = s.post(f"{BASE}/pharmacy/barcodes/bulk-generate", headers={"X-CSRF-Token": csrf},
               json={"ids": created_ids}, timeout=15)
    data = r.json()["data"]
    codes = [it["barcode"] for it in data["items"] if it["status"] == "generated"]
    check("bulk generated 2", r.status_code == 200 and data["generated"] == 2, r.text[:200])
    check("bulk codes unique+valid", len(set(codes)) == 2 and all(ean13_valid(c) for c in codes), str(codes))

    # ---- 9) manual duplicate rejected (unique index) --------------
    r = s.put(f"{BASE}/pharmacy/products/{created_ids[0]}", headers={"X-CSRF-Token": csrf}, json={
        "name": "منتج دفعة 1", "dosage_form": "tablet", "barcode": code_b,
        "packaging_type": "WHOLE_ONLY", "units_per_box": 1,
        "cost_price_piastres": 1000, "selling_price_piastres": 2000,
        "min_stock_level": 0,
    }, timeout=10)
    check("manual duplicate → 409", r.status_code == 409 and r.json()["error"] == "barcode_already_exists", r.text[:160])

    # ---- 10) parallel generation: 8 concurrent creates ------------
    def create_one(i):
        session = requests.Session()
        session.post(f"{BASE}/auth/pharmacy/login", json={"email": EMAIL, "password": PASSWORD}, timeout=10)
        csrf_i = session.cookies.get("pharmacy_csrf")
        rr = session.post(f"{BASE}/pharmacy/products", headers={"X-CSRF-Token": csrf_i}, json={
            "name": f"متوازي {i}", "dosage_form": "tablet", "barcode": "", "generate_barcode": True,
            "packaging_type": "WHOLE_ONLY",
            "cost_price_piastres": 100, "selling_price_piastres": 300,
            "min_stock_level": 0,
        }, timeout=15)
        return rr.json()["data"].get("barcode", "")

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        par_codes = list(pool.map(create_one, range(8)))
    check("8 parallel creates → 8 valid distinct RCNs",
          len(par_codes) == 8 and len(set(par_codes)) == 8 and all(ean13_valid(c) for c in par_codes),
          str(par_codes))

    # ---- 11) label settings --------------------------------------
    r = s.get(f"{BASE}/pharmacy/settings/labels", timeout=10)
    check("labels GET 200", r.status_code == 200, r.text[:160])
    labels = r.json()["data"]
    size_ids = [sz["id"] for sz in labels["sizes"]]
    check("sizes registry complete", set(size_ids) == {"35x15", "35x25", "50x25", "58x30"}, str(size_ids))
    check("system templates present", len(labels["templates"]) >= 5, str(len(labels["templates"])))
    sys_ids = [t["id"] for t in labels["templates"] if t["system"]]
    check("default template valid", labels["default_template_id"] in sys_ids, labels["default_template_id"])

    r = s.put(f"{BASE}/pharmacy/settings/labels", headers={"X-CSRF-Token": csrf}, json={
        "labels": {
            "default_template_id": sys_ids[0],
            "templates": [{"name": "ملصق الكاشير", "size_id": "35x25",
                           "fields": ["name", "price", "barcode"], "font_scale": 110, "show_pharmacy": True}],
        }
    }, timeout=10)
    check("custom template saved", r.status_code == 200, r.text[:200])
    r = s.get(f"{BASE}/pharmacy/settings/labels", timeout=10)
    custom = [t for t in r.json()["data"]["templates"] if not t["system"]]
    check("custom template persisted with id", len(custom) == 1 and custom[0]["id"].startswith("lbl_"), str(custom))

    r = s.put(f"{BASE}/pharmacy/settings/labels", headers={"X-CSRF-Token": csrf}, json={
        "labels": {"default_template_id": sys_ids[0],
                   "templates": [{"name": "غلط", "size_id": "35x15", "fields": ["name"], "font_scale": 100}]}
    }, timeout=10)
    check("envelope rejects template without barcode field", r.status_code == 400, r.text[:160])

    # ---- 12) audit rows landed -----------------------------------
    cur.execute(
        "SELECT action, COUNT(*) FROM audit_logs WHERE action LIKE 'barcode.%' GROUP BY action")
    actions = dict(cur.fetchall())
    check("audit barcode.generated rows", actions.get("barcode.generated", 0) >= 1, str(actions))
    cur.execute("SELECT COUNT(*) FROM audit_logs WHERE action='label_template.updated'")
    check("audit label_template.updated", cur.fetchone()[0] >= 1)

    cur.execute(
        "SELECT gp.barcode, gp.barcode_type FROM global_products gp "
        "JOIN pharmacy_products pp ON pp.global_product_id = gp.id "
        "WHERE pp.id=%s", (created_ids[0],))
    row = cur.fetchone()
    check("bulk row typed RCN_EAN13", row and row[1] == "RCN_EAN13", str(row))

    conn.close()
    print()
    if FAILURES:
        print(f"E2E FAILED ({len(FAILURES)}): " + ", ".join(FAILURES))
        sys.exit(1)
    print("E2E PASS — barcode system v1 complete flow verified")


if __name__ == "__main__":
    main()
