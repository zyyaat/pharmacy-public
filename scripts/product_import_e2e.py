#!/usr/bin/env python3
"""Task 41 — اختبارات API لاستيراد المنتجات (ترحيل الملفات القديمة).

يشغَّل عبر scripts/dev-up.sh (الخدمات في نفس استدعاء shell).
يولد ملفات xlsx/CSV حقيقية عبر openpyxl ويختبر المعاينة والتنفيذ والتقرير.
"""
import io
import os
import sys
import time

import requests
from openpyxl import Workbook

BASE = "http://127.0.0.1:8080/api/v1"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"
RUN = str(int(time.time()))[-6:]  # أسماء فريدة كل تشغيل

checks = []


def check(name, cond, extra=""):
    checks.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL"), "-", name, extra if not cond else "")


def make_xlsx(rows, headers=None):
    wb = Workbook()
    ws = wb.active
    ws.append(headers or ["اسم الصنف", "الباركود", "السعر", "سعر الشراء", "سعر الشريط",
                          "عدد الشرائط بالعلبة", "الكمية", "حد الطلب", "الصلاحية", "رقم التشغيلة"])
    for r in rows:
        ws.append(r)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def main():
    # تسجيل الدخول
    s = requests.Session()
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": EMAIL, "password": PASSWORD}, timeout=10)
    check("login", r.status_code == 200)
    csrf = s.cookies.get("pharmacy_csrf")
    hdr = {"X-CSRF-Token": csrf} if csrf else {}

    # قالب CSV يفتح بنجاح
    r = s.get(f"{BASE}/pharmacy/imports/products/template", timeout=10)
    check("template 200", r.status_code == 200)
    check("template BOM", r.content[:3] == b"\xef\xbb\xbf")
    check("template rows", "بانادول اكسترا" in r.text and "اسم الصنف" in r.text)

    # ============ المعاينة ============
    xlsx = make_xlsx([
        [f"استيراد ايميبرازول {RUN}", f"991{RUN}1", "١٢٫٥", "8", "2", "12", "5", "3", "2027-05-01", "IMP-A"],
        [f"استيراد فولتارين جل {RUN}", f"991{RUN}2", "30", "20", "", "6", "3", "2", "", ""],
        ["مرهم جروح", "9800415", "9", "", "", "", "2", "", "", ""],
        [f"صف تالف {RUN}", "", "10", "", "", "12.5", "", "", "", ""],
        ["", "", "", "", "", "", "", "", "", ""],
    ])
    r = s.post(f"{BASE}/pharmacy/imports/products/preview", headers=hdr,
               files={"file": ("import.xlsx", xlsx, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
               timeout=15)
    check("preview 200", r.status_code == 200, r.text[:200])
    pv = r.json()["data"]
    check("preview total=4 (فارغ مُهمل)", pv["total_rows"] == 4, pv["total_rows"])
    check("mapping name=0", pv["mapping"]["name"] == 0)
    check("mapping barcode=1", pv["mapping"]["barcode"] == 1)
    check("mapping upb detected", pv["mapping"]["units_per_box"] == 5, pv["mapping"])
    check("mapping min detected", pv["mapping"]["min_stock_level"] == 7, pv["mapping"])
    check("estimate valid=3", pv["valid_estimate"] == 3, pv["valid_estimate"])
    check("estimate invalid=1", pv["invalid_estimate"] == 1, pv["invalid_estimate"])

    # ملف صيغة غير مدعومة
    r = s.post(f"{BASE}/pharmacy/imports/products/preview", headers=hdr,
               files={"file": ("old.xls", b"\xd0\xcf\x11\xe0", "application/vnd.ms-excel")}, timeout=10)
    check("xls rejected with hint", r.status_code == 400 and "xlsx" in r.json().get("message", ""), r.text[:150])

    # ============ التنفيذ (استراتيجية: تجاهل المكرر) ============
    mapping = pv["mapping"]
    options = {"duplicate_strategy": "skip", "quantity_unit": "box", "import_stock": True}
    r = s.post(f"{BASE}/pharmacy/imports/products/execute", headers=hdr,
               data={"mapping": __import__("json").dumps(mapping), "options": __import__("json").dumps(options)},
               files={"file": ("import.xlsx", xlsx)}, timeout=30)
    check("execute 200", r.status_code == 200, r.text[:300])
    rep = r.json()["data"]
    check("created=2", rep["created"] == 2, rep)
    check("skipped=1 (مرهم جروح)", rep["skipped"] == 1, rep)
    check("failed=1", rep["failed"] == 1, rep)
    check("error mentions upb", any("عدد الشرائط" in e["reason"] for e in rep["errors"]), rep["errors"])
    check("stock_lines=2", rep["stock_lines"] == 2, rep)

    # التحقق من قاعدة البيانات: الأسعار بالقروش + الأرقام العربية + الرصيد
    import psycopg2
    conn = psycopg2.connect(os.environ.get("DATABASE_URL", "postgresql://postgres@127.0.0.1:54329/reports_test"))
    cur = conn.cursor()
    cur.execute("""
        SELECT pp.selling_price::bigint, pp.partial_selling_price::bigint, pp.units_per_box, pp.min_stock_level::bigint
        FROM pharmacy_products pp JOIN global_products gp ON gp.id = pp.global_product_id
        WHERE gp.barcode = %s
    """, (f"991{RUN}1",))
    row = cur.fetchone()
    check("arabic price ١٢٫٥=1250", row and row[0] == 1250, row)
    check("partial explicit 200", row and row[1] == 200, row)
    cur.execute("""
        SELECT b.quantity, b.unit, b.cost_per_unit FROM inventory_batches b
        JOIN pharmacy_products pp ON pp.id = b.pharmacy_product_id
        JOIN global_products gp ON gp.id = pp.global_product_id
        WHERE gp.barcode = %s
    """, (f"991{RUN}1",))
    b = cur.fetchone()
    check("batch 5 boxes*12=60 strips", b and b[0] == 60, b)
    check("batch unit strip", b and b[1] == "strip", b)
    check("batch cost 800/12≈67", b and b[2] == 67, b)
    cur.execute("""
        SELECT pp.selling_price::bigint, pp.partial_selling_price::bigint FROM pharmacy_products pp
        JOIN global_products gp ON gp.id = pp.global_product_id WHERE gp.barcode = %s
    """, (f"991{RUN}2",))
    v = cur.fetchone()
    check("fallback partial floor(3000/6)=500", v and v[1] == 500, v)
    conn.commit()
    conn.close()

    # ============ تحديث المكرر ============
    xlsx2 = make_xlsx([
        ["مرهم جروح", "9800415", "9.99", "", "", "", "", "4", "", ""],
    ])
    r = s.post(f"{BASE}/pharmacy/imports/products/preview", headers=hdr,
               files={"file": ("upd.xlsx", xlsx2)}, timeout=15)
    mp = r.json()["data"]["mapping"]
    options = {"duplicate_strategy": "update", "quantity_unit": "box", "import_stock": False}
    r = s.post(f"{BASE}/pharmacy/imports/products/execute", headers=hdr,
               data={"mapping": __import__("json").dumps(mp), "options": __import__("json").dumps(options)},
               files={"file": ("upd.xlsx", xlsx2)}, timeout=30)
    rep = r.json()["data"]
    check("update: updated=1", rep["updated"] == 1, rep)
    import psycopg2 as pg2
    conn = pg2.connect(os.environ.get("DATABASE_URL", "postgresql://postgres@127.0.0.1:54329/reports_test"))
    cur = conn.cursor()
    cur.execute("""
        SELECT pp.selling_price::bigint, pp.min_stock_level::bigint FROM pharmacy_products pp
        JOIN global_products gp ON gp.id = pp.global_product_id WHERE gp.barcode = '9800415'
    """)
    v = cur.fetchone()
    check("updated price 9.99=999", v and v[0] == 999, v)
    check("updated min=4", v and v[1] == 4, v)
    conn.commit()
    conn.close()

    # ============ CSV مع BOM وأرقام عربية ============
    csv_content = "اسم الصنف,الباركود,السعر,عدد الشرائط بالعلبة,الكمية\n" + \
        f"استيراد CSV صنف {RUN},992{RUN},١٥,10,2\n"
    csv_bytes = b"\xef\xbb\xbf" + csv_content.encode("utf-8")
    r = s.post(f"{BASE}/pharmacy/imports/products/preview", headers=hdr,
               files={"file": ("old-export.csv", csv_bytes, "text/csv")}, timeout=10)
    check("csv preview 200", r.status_code == 200, r.text[:200])
    cpv = r.json()["data"]
    check("csv mapping name", cpv["mapping"]["name"] == 0)
    check("csv mapping qty", cpv["mapping"]["quantity"] == 4, cpv["mapping"])
    options = {"duplicate_strategy": "skip", "quantity_unit": "box", "import_stock": True}
    r = s.post(f"{BASE}/pharmacy/imports/products/execute", headers=hdr,
               data={"mapping": __import__("json").dumps(cpv["mapping"]), "options": __import__("json").dumps(options)},
               files={"file": ("old-export.csv", csv_bytes)}, timeout=30)
    rep = r.json()["data"]
    check("csv created=1", rep["created"] == 1, rep)
    import psycopg2 as pg3
    conn = pg3.connect(os.environ.get("DATABASE_URL", "postgresql://postgres@127.0.0.1:54329/reports_test"))
    cur = conn.cursor()
    cur.execute("""
        SELECT pp.selling_price::bigint FROM pharmacy_products pp
        JOIN global_products gp ON gp.id = pp.global_product_id WHERE gp.barcode = %s
    """, (f"992{RUN}",))
    v = cur.fetchone()
    check("csv arabic price ١٥=1500", v and v[0] == 1500, v)
    conn.commit()
    conn.close()

    failed = [n for n, ok in checks if not ok]
    print(f"\n== {len(checks) - len(failed)}/{len(checks)} passed ==")
    if failed:
        print("FAILED:", failed)
        sys.exit(1)


if __name__ == "__main__":
    main()
