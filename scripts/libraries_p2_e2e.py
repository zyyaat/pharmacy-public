#!/usr/bin/env python3
"""e2e المرحلة 2 — استيراد المكتبات ومزامنتها من جهة الصيدلية.

يغطي: الرؤية حسب البلد، حالة المزامنة، المعاينة بالبوابات الثلاث
(اختيار/كشف تكرار/سقف خطة)، التنفيذ، القواعد الحمراء (المخزون والتكلفة
لا يُمسّان وسعر البيع يتبع الرسمي)، النشر v2 ← سحب الفروقات ← المزامنة،
السحب المعلوماتي للمنتجات، وسجلات التدقيق.

يُشغَّل عبر scripts/run_libraries_p2_e2e.sh في استدعاء shell واحد.
"""
import os
import sys
import time

import psycopg2
import requests

BASE = "http://127.0.0.1:8080/api/v1"
ADMIN_EMAIL = os.environ.get("BOOTSTRAP_SUPER_ADMIN_EMAIL", "admin@pharmacy-os.test")
ADMIN_PASSWORD = os.environ.get("BOOTSTRAP_SUPER_ADMIN_PASSWORD", "Str0ng!Admin2026")
PH_EMAIL = f"lib-p2-{str(int(time.time()))[-6:]}@test.io"
PH_PASSWORD = "Str0ng!Pass2026"
DB = os.environ.get("E2E_DATABASE_URL", "postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable")
RUN = str(int(time.time()))[-6:]

checks = []


def check(name, cond, extra=""):
    checks.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL"), "-", name, extra if not cond else "")


def db_one(query, args=()):
    conn = psycopg2.connect(DB)
    try:
        cur = conn.cursor()
        cur.execute(query, args)
        row = cur.fetchone()
        conn.commit()
        return row
    finally:
        conn.close()


def db_exec(query, args=()):
    conn = psycopg2.connect(DB)
    try:
        cur = conn.cursor()
        cur.execute(query, args)
        conn.commit()
        return cur.rowcount
    finally:
        conn.close()


def main():
    # ================= تجهيز الصيدلية =================
    ph = requests.Session()
    r = ph.post(f"{BASE}/auth/register", json={
        "company_name": f"صيدلية المكتبات {RUN}", "company_email": PH_EMAIL,
        "first_name": "أحمد", "last_name": "الصيدلي",
        "email": PH_EMAIL, "password": PH_PASSWORD,
    }, timeout=10)
    check("pharmacy register", r.status_code in (200, 201), f"{r.status_code} {r.text[:200]}")
    db_exec("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (PH_EMAIL,))
    db_exec(
        "UPDATE pharmacies SET settings = settings || '{\"onboarding\": {\"completed\": true}}'::jsonb "
        "WHERE account_id IN (SELECT id FROM accounts WHERE contact_email=%s)",
        (PH_EMAIL,))
    # الصيدلية المصرية: البلد EG (مثل الواقع) — حاسم لاختبار الرؤية
    db_exec(
        "UPDATE pharmacies SET country='EG' WHERE account_id IN "
        "(SELECT id FROM accounts WHERE contact_email=%s)",
        (PH_EMAIL,))
    r = ph.post(f"{BASE}/auth/pharmacy/login", json={"email": PH_EMAIL, "password": PH_PASSWORD}, timeout=10)
    check("pharmacy login", r.status_code == 200, f"{r.status_code} {r.text[:200]}")
    csrf = ph.cookies.get("pharmacy_csrf")
    ph_hdr = {"X-CSRF-Token": csrf} if csrf else {}

    # منتجات الصيدلية القائمة (لأغراض كشف التكرار والقواعد الحمراء)
    r = ph.post(f"{BASE}/pharmacy/products", headers=ph_hdr, json={
        "name": "بانادول أدفانس", "generic_name": "Paracetamol", "dosage_form": "tablet",
        "strength": "500mg", "barcode": f"980{RUN}10", "packaging_type": "BOX_STRIP",
        "units_per_box": 5, "cost_price_piastres": 8000, "selling_price_piastres": 10000,
        "partial_selling_price_piastres": 2000, "min_stock_level": 0,
        "initial_boxes": 2, "initial_strips": 1, "batch_number": "RP-A",
        "expiry_date": "2027-06-01",
    }, timeout=10)
    check("pharmacy product A", r.status_code in (200, 201), f"{r.status_code} {r.text[:200]}")
    panadol_pp = r.json()["data"]["id"]
    panadol_gp = r.json()["data"]["global_product_id"]

    r = ph.post(f"{BASE}/pharmacy/products", headers=ph_hdr, json={
        "name": "كونجستال", "generic_name": "Paracetamol", "dosage_form": "tablet",
        "strength": "500mg", "barcode": f"980{RUN}11", "packaging_type": "WHOLE_ONLY",
        "units_per_box": 1, "cost_price_piastres": 1500, "selling_price_piastres": 2000,
        "min_stock_level": 0, "initial_boxes": 4, "initial_strips": 0, "batch_number": "RP-B",
    }, timeout=10)
    check("pharmacy product B", r.status_code in (200, 201), f"{r.status_code}")

    r = ph.post(f"{BASE}/pharmacy/products", headers=ph_hdr, json={
        "name": "استامول", "generic_name": "Paracetamol", "dosage_form": "tablet",
        "strength": "500mg", "barcode": f"980{RUN}13", "packaging_type": "WHOLE_ONLY",
        "units_per_box": 1, "cost_price_piastres": 900, "selling_price_piastres": 1300,
        "min_stock_level": 0, "initial_boxes": 2, "initial_strips": 0, "batch_number": "RP-C",
    }, timeout=10)
    check("pharmacy product C (استامول)", r.status_code in (200, 201), f"{r.status_code}")

    # مخزون البانادول قبل الاستيراد (2 علب + 1 شريط = 11 وحدة أساسية)
    gp_row = db_one("SELECT id::text FROM global_products WHERE id=%s", (panadol_gp,))
    check("gp exists", gp_row is not None)

    # ================= المكتبة من جهة المسؤول =================
    ad = requests.Session()
    r = ad.post(f"{BASE}/auth/platform/login", json={"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD}, timeout=10)
    check("admin login", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    ad_hdr = {"X-CSRF-Token": ad.cookies.get("platform_csrf")} if ad.cookies.get("platform_csrf") else {}

    r = ad.post(f"{BASE}/platform-admin/libraries", headers=ad_hdr, json={
        "name": f"مكتبة مصر P2 {RUN}", "description": "أسعار رسمية", "country_code": "EG",
        "currency": "EGP"}, timeout=10)
    check("create library", r.status_code in (200, 201), f"{r.status_code} {r.text[:200]}")
    lib_id = r.json()["data"]["id"]

    # 1) منتج الصيدلية نفسه (global product) → already_have عند الاستيراد
    r = ad.post(f"{BASE}/platform-admin/libraries/{lib_id}/products", headers=ad_hdr, json={
        "global_product_id": panadol_gp, "official_price_piastres": 11000}, timeout=10)
    check("add pharmacy gp to library", r.status_code in (200, 201), f"{r.status_code} {r.text[:200]}")

    # 2) اسم مشابه لمنتج الصيدلية بباركود مختلف → مرشّح مراجعة (ربط صريح)
    r = ad.post(f"{BASE}/platform-admin/libraries/{lib_id}/products", headers=ad_hdr, json={
        "official_price_piastres": 2500,
        "new_product": {"name": "كونجستال أدفانس", "dosage_form": "tablet",
                        "barcode": f"980{RUN}12", "strength": "500mg"}}, timeout=10)
    check("add suspect-twin product", r.status_code in (200, 201), f"{r.status_code} {r.text[:200]}")
    twin_gp = r.json()["data"]["global_product_id"]

    # 3) منتج جديد كليًا (بسعر رسمي)
    r = ad.post(f"{BASE}/platform-admin/libraries/{lib_id}/products", headers=ad_hdr, json={
        "official_price_piastres": 3000,
        "new_product": {"name": f"دواء جديد {RUN}", "dosage_form": "syrup",
                        "barcode": f"980{RUN}99"}}, timeout=10)
    check("add fresh product", r.status_code in (200, 201), f"{r.status_code}")
    fresh_gp = r.json()["data"]["global_product_id"]

    # 4) منتج مرشّح ثانٍ بلا باركود (يُستورد كجديد — بسعر رسمي)
    r = ad.post(f"{BASE}/platform-admin/libraries/{lib_id}/products", headers=ad_hdr, json={
        "official_price_piastres": 1500,
        "new_product": {"name": "استامول اكسترا", "dosage_form": "tablet"}}, timeout=10)
    check("add extra product", r.status_code in (200, 201), f"{r.status_code}")
    extra_gp = r.json()["data"]["global_product_id"]

    # 5) نجد صف منتج كونجستال عند الصيدلية (هدف الربط الصريح)
    r = ph.get(f"{BASE}/pharmacy/products", timeout=10)
    check("pharmacy products listed", r.status_code == 200, f"{r.status_code}")
    kongestal_pp = next((p["id"] for p in r.json()["data"] if p["name"] == "كونجستال"), None)
    check("found kongestal pp id", kongestal_pp is not None)

    r = ad.post(f"{BASE}/platform-admin/libraries/{lib_id}/publish", headers=ad_hdr, timeout=10)
    check("publish v1", r.status_code == 200 and r.json()["data"]["version"] == 1,
          f"{r.status_code} {r.text[:200]}")

    # ================= الرؤية وحالة المزامنة =================
    r = ph.get(f"{BASE}/pharmacy/libraries", timeout=10)
    libs = r.json()["data"]
    check("list visible libraries", r.status_code == 200 and len(libs) >= 1, f"{r.status_code} {len(libs)}")
    mine = next((x for x in libs if x["id"] == lib_id), None)
    check("library visible with status not_imported", mine and mine["sync_status"] == "not_imported",
          str(mine))
    check("product_count 4", mine and mine["product_count"] == 4, str(mine and mine["product_count"]))

    # مكتبة بلد آخر غير مرئية
    r = ad.post(f"{BASE}/platform-admin/libraries", headers=ad_hdr, json={
        "name": f"مكتبة سعودية {RUN}", "country_code": "SA", "currency": "SAR"}, timeout=10)
    sa_lib = r.json()["data"]["id"]
    ad.post(f"{BASE}/platform-admin/libraries/{sa_lib}/products", headers=ad_hdr, json={
        "new_product": {"name": f"دواء سعودي {RUN}", "dosage_form": "tablet"}}, timeout=10)
    ad.post(f"{BASE}/platform-admin/libraries/{sa_lib}/publish", headers=ad_hdr, timeout=10)
    r = ph.get(f"{BASE}/pharmacy/libraries", timeout=10)
    ids = [x["id"] for x in r.json()["data"]]
    check("SA library hidden for EG pharmacy", sa_lib not in ids, str(ids))

    # ================= المعاينة (البوابات الثلاث) =================
    r = ph.post(f"{BASE}/pharmacy/libraries/{lib_id}/import/preview", headers=ph_hdr,
                json={"mode": "all"}, timeout=10)
    d = r.json().get("data", {})
    check("preview ok", r.status_code == 200, f"{r.status_code} {r.text[:300]}")
    cands = {x["global_product_id"]: x for x in d.get("candidates", [])}
    check("preview: already_have for own gp", cands.get(panadol_gp, {}).get("suggested_action") == "already_have", str(cands.get(panadol_gp)))
    check("preview: name twin surfaces matches", cands.get(twin_gp, {}).get("matches"), str(cands.get(twin_gp)))
    check("preview: fresh suggests create", cands.get(fresh_gp, {}).get("suggested_action") == "create_new",
          str(cands.get(fresh_gp)))
    check("preview: plan info present", "products_limit" in d.get("plan", {}), str(d.get("plan")))

    # ================= التنفيذ + القواعد الحمراء =================
    r = ph.post(f"{BASE}/pharmacy/libraries/{lib_id}/import/execute", headers=ph_hdr, json={
        "items": [
            {"global_product_id": panadol_gp, "action": "create"},
            {"global_product_id": twin_gp, "action": "link", "pharmacy_product_id": kongestal_pp},
            {"global_product_id": fresh_gp, "action": "create"},
            {"global_product_id": extra_gp, "action": "create"},
        ]}, timeout=15)
    d = r.json().get("data", {})
    check("execute ok", r.status_code == 200, f"{r.status_code} {r.text[:300]}")
    check("execute created 2 (fresh+extra)", d.get("products_created") == 2, str(d))
    check("execute linked 1 (twin)", d.get("products_linked") == 1, str(d))
    check("execute price_updated 1 (own gp)", d.get("prices_updated") == 1, str(d))
    check("execute applied 4", d.get("applied") == 4, str(d))

    # القاعدة الحمراء: المخزون والتكلفة سليمان، سعر البيع رسمي
    row = db_one("""SELECT pp.selling_price, pp.cost_price,
                    (SELECT COUNT(*) FROM inventory_batches ib WHERE ib.pharmacy_product_id = pp.id),
                    (SELECT COALESCE(SUM(sm.quantity),0) FROM stock_movements sm
                       JOIN inventory_batches ib ON ib.id = sm.batch_id
                       WHERE ib.pharmacy_product_id = pp.id)
                    FROM pharmacy_products pp WHERE pp.id = %s""", (panadol_pp,))
    check("RED LINE: selling = official 11000", row and row[0] == 11000, str(row))
    check("RED LINE: cost untouched 8000", row and row[1] == 8000, str(row))
    check("RED LINE: batches untouched (1)", row and row[2] == 1, str(row))
    check("RED LINE: stock untouched (11)", row and row[3] == 11, str(row))

    # ربط التوأم: صف كونجستال عند الصيدلية أصبح يشير لمنتج المكتبة
    # بسعر البيع الرسمي، والتكلفة القديمة كما هي.
    row = db_one("""SELECT pp.global_product_id::text, pp.selling_price, pp.cost_price
                    FROM pharmacy_products pp WHERE pp.id = %s""", (kongestal_pp,))
    check("twin linked to library gp at official price",
          row and row[0] == twin_gp and row[1] == 2500, str(row))

    # الصيدلية لا تملك صفوف مخزون للمنتجات الجديدة
    row = db_one("""SELECT (SELECT COUNT(*) FROM inventory_batches ib
                    JOIN pharmacy_products pp ON pp.id = ib.pharmacy_product_id
                    WHERE pp.global_product_id = %s)""", (fresh_gp,))
    check("new product has zero batches", row and row[0] == 0, str(row))

    # حالة المزامنة أصبحت up_to_date
    r = ph.get(f"{BASE}/pharmacy/libraries", timeout=10)
    mine = next((x for x in r.json()["data"] if x["id"] == lib_id), None)
    check("status up_to_date after import", mine and mine["sync_status"] == "up_to_date", str(mine))

    # ================= النشر v2: تغيير سعر + إضافة + سحب =================
    r = ad.get(f"{BASE}/platform-admin/libraries/{lib_id}/products", timeout=10)
    lp_rows = {x["global_product_id"]: x["id"] for x in r.json()["data"]}
    r = ad.put(f"{BASE}/platform-admin/libraries/{lib_id}/products/{lp_rows[panadol_gp]}",
               headers=ad_hdr, json={"official_price_piastres": 12500}, timeout=10)
    check("admin price change", r.status_code == 200, f"{r.status_code} {r.text[:200]}")
    r = ad.post(f"{BASE}/platform-admin/libraries/{lib_id}/products", headers=ad_hdr, json={
        "official_price_piastres": 4200,
        "new_product": {"name": f"منتج إضافي v2 {RUN}", "dosage_form": "tablet",
                        "barcode": f"980{RUN}88"}}, timeout=10)
    v2_gp = r.json()["data"]["global_product_id"]
    check("admin adds v2 product", r.status_code in (200, 201), f"{r.status_code}")
    # منتج v2 بلا سعر رسمي → حارس no_official_price يجب أن يمنعه من الوصول للصيدلية
    r = ad.post(f"{BASE}/platform-admin/libraries/{lib_id}/products", headers=ad_hdr, json={
        "new_product": {"name": f"منتج بلا سعر {RUN}", "dosage_form": "tablet"}}, timeout=10)
    check("admin adds unpriced v2 product", r.status_code in (200, 201), f"{r.status_code}")
    r = ad.delete(f"{BASE}/platform-admin/libraries/{lib_id}/products/{lp_rows[fresh_gp]}",
                  headers=ad_hdr, timeout=10)
    check("admin removes fresh product", r.status_code == 200, f"{r.status_code} {r.text[:150]}")

    r = ad.post(f"{BASE}/platform-admin/libraries/{lib_id}/publish", headers=ad_hdr, timeout=10)
    check("publish v2", r.status_code == 200 and r.json()["data"]["version"] == 2,
          f"{r.status_code} {r.text[:200]}")

    # ================= شارة التحديث + الفروقات + السحب =================
    r = ph.get(f"{BASE}/pharmacy/libraries", timeout=10)
    mine = next((x for x in r.json()["data"] if x["id"] == lib_id), None)
    check("update_available badge", mine and mine["sync_status"] == "update_available", str(mine))
    check("pending changes >= 3", mine and mine["pending_changes"] >= 3, str(mine and mine["pending_changes"]))

    r = ph.get(f"{BASE}/pharmacy/libraries/{lib_id}/diff", timeout=10)
    d = r.json().get("data", {})
    counts = d.get("counts", {})
    check("diff has price_changed 1", counts.get("price_changed") == 1, str(counts))
    check("diff has added 2", counts.get("added") == 2, str(counts))
    check("diff has removed 1", counts.get("removed") == 1, str(counts))

    r = ph.post(f"{BASE}/pharmacy/libraries/{lib_id}/sync", headers=ph_hdr, timeout=15)
    d = r.json().get("data", {})
    check("sync ok", r.status_code == 200 and d.get("synced"), f"{r.status_code} {r.text[:300]}")
    check("sync prices_updated 1", d.get("prices_updated") == 1, str(d))
    check("sync products_added 1", d.get("products_added") == 1, str(d))
    check("sync skips unpriced product", any(s.get("reason") == "no_official_price" for s in d.get("skipped", [])), str(d.get("skipped")))
    check("sync removed info 1 (kept ownership)", len(d.get("removed", [])) == 1, str(d.get("removed")))

    # بعد السحب: السعر 12500، والمنتج المسحوب ما زال ملك الصيدلية بسعره القديم
    row = db_one("""SELECT pp.selling_price FROM pharmacy_products pp WHERE pp.id = %s""", (panadol_pp,))
    check("price pulled to 12500", row and row[0] == 12500, str(row))
    row = db_one("""SELECT pp.selling_price, pp.cost_price FROM pharmacy_products pp
                    WHERE pp.global_product_id = %s AND pp.pharmacy_id IN
                    (SELECT id FROM pharmacies WHERE account_id IN
                     (SELECT id FROM accounts WHERE contact_email=%s))""",
                 (fresh_gp, PH_EMAIL))
    check("RED LINE: removed product still owned (price 3000, cost 0)",
          row and row[0] == 3000 and row[1] == 0, str(row))

    # مزامنة ثانية → لا شيء
    r = ph.post(f"{BASE}/pharmacy/libraries/{lib_id}/sync", headers=ph_hdr, timeout=10)
    d = r.json().get("data", {})
    check("re-sync nothing_to_do", d.get("nothing_to_do") is True, str(d))

    # مزامنة مكتبة لم تُستورد → 400
    r = ph.post(f"{BASE}/pharmacy/libraries/{sa_lib}/sync", headers=ph_hdr, timeout=10)
    check("sync un-imported library 400/404", r.status_code in (400, 404), f"{r.status_code}")

    # ================= التدقيق (tenant audit) =================
    row = db_one("""SELECT COUNT(*) FROM audit_logs WHERE action IN ('libraries.import','libraries.sync')""")
    check("tenant audit rows exist", row and row[0] >= 2, str(row))

    # ================= خلاصة =================
    failed = [name for name, ok in checks if not ok]
    print(f"\n{len(checks) - len(failed)}/{len(checks)} PASSED")
    if failed:
        print("FAILED:", failed)
        sys.exit(1)


if __name__ == "__main__":
    main()
