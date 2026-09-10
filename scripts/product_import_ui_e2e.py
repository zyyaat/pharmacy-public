#!/usr/bin/env python3
"""Task 41 — اختبار UI لمعالج ترحيل المنتجات (playwright).

يشغَّل عبر scripts/run_import_e2e.sh بعد جاهزية الخدمات.
"""
import io
import sys
import time

from openpyxl import Workbook
from playwright.sync_api import sync_playwright

APP = "http://localhost:3000"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"
RUN = str(int(time.time()))[-6:]

FAILURES = []


def check(name, cond, detail=""):
    print(f"  [{'PASS' if cond else 'FAIL'}] {name} {detail}")
    if not cond:
        FAILURES.append(name)


def current_url(page):
    try:
        return page.evaluate("window.location.href")
    except Exception:
        return page.url


def main():
    # ملف xlsx للمعالج عبر الواجهة: صنفان جديدان + مكرر
    wb = Workbook()
    ws = wb.active
    ws.append(["اسم الصنف", "الباركود", "السعر", "عدد الشرائط بالعلبة", "الكمية", "حد الطلب"])
    ws.append([f"UI ترحيل بانادول {RUN}", f"993{RUN}1", "20", "8", "3", "2"])
    ws.append([f"UI ترحيل كونجستال {RUN}", f"993{RUN}2", "35", "", "5", ""])
    ws.append(["مرهم جروح", "9800415", "5", "", "", ""])
    buf = io.BytesIO()
    wb.save(buf)
    xlsx_bytes = buf.getvalue()

    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        page = ctx.new_page()

        # تسجيل الدخول
        page.goto(f"{APP}/login", wait_until="networkidle")
        page.fill('input[type="email"]', EMAIL)
        page.fill('input[type="password"]', PASSWORD)
        page.click('button[type="submit"]')
        deadline = time.time() + 20
        while time.time() < deadline:
            if current_url(page).rstrip("/") == APP:
                break
            time.sleep(0.2)
        check("تسجيل الدخول", "/login" not in current_url(page), current_url(page))

        # ---------- A) القائمة الجانبية للإعدادات تتضمن ترحيل المنتجات ----------
        page.goto(f"{APP}/settings/receipts", wait_until="networkidle")
        page.wait_for_selector('text=مقاس الورقة', timeout=15000)
        check("قسم «ترحيل المنتجات» في قائمة الإعدادات الجانبية",
              page.locator('nav[aria-label="أقسام الإعدادات"] a', has_text="ترحيل المنتجات").count() == 1)
        check("العودة للرئيسية متاحة في شريط الإعدادات",
              page.locator('a', has_text="العودة للرئيسية").count() == 1)

        # ---------- B) الخطوة 1: رفع الملف ----------
        page.click('nav[aria-label="أقسام الإعدادات"] a:has-text("ترحيل المنتجات")')
        page.wait_for_selector('text=ارفع ملف المنتجات القديمة', timeout=15000)
        check("صفحة الترحيل فتحت بمسارها الخاص",
              "/settings/import" in current_url(page), current_url(page))
        check("مؤشر الخطوات الثلاث ظاهر",
              page.locator('ol[aria-label="خطوات الترحيل"] li').count() == 3)
        check("زر تنزيل النموذج متاح",
              page.locator('[data-testid="import-template-btn"]').count() == 1)

        page.set_input_files('[data-testid="import-file-input"]',
                             {"name": f"ui-import-{RUN}.xlsx", "mimeType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                              "buffer": xlsx_bytes})

        # ---------- C) الخطوة 2: المعاينة والربط ----------
        page.wait_for_selector('text=ربط الأعمدة', timeout=20000)
        check("انتقل للخطوة 2 (المعاينة)", "ربط الأعمدة" in page.content())
        check("الربط المقترح: اسم الصنف على العمود الأول",
              page.locator('label', has_text="اسم الصنف").count() >= 1)
        check("شارات الملف تظهر النوع xlsx", page.locator('text=xlsx').count() >= 1)
        check("عينة الصفوف تعرض صنفًا من الملف",
              page.locator('table').count() >= 1 and f"UI ترحيل بانادول {RUN}" in page.content())
        check("خيارا سياسة التكرار ظاهران",
              page.locator('input[name="duplicate_strategy"]').count() == 2)

        # ---------- D) الخطوة 3: التنفيذ والتقرير ----------
        page.click('[data-testid="import-execute-btn"]')
        page.wait_for_selector('[data-testid="import-report"]', timeout=20000)
        report_text = page.locator('[data-testid="import-report"]').inner_text()
        check("التقرير يظهر الأربع حالات",
              all(w in report_text for w in ["أُنشئ", "حُدِّث", "تُخِطي", "رُفض"]), report_text)
        check("التقرير يحتوي بطاقة تخطي المكرر (مرهم جروح)", "تُخِطي" in report_text)
        check("أزرار ما بعد الترحيل متاحة",
              page.locator('button', has_text="ترحيل ملف آخر").count() == 1
              and page.locator('button', has_text="فتح صفحة المخزون").count() == 1)

        browser.close()

    # ---------- E) تحقق قاعدي: الأصناف المستوردة عبر الواجهة ----------
    import psycopg2
    conn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable")
    cur = conn.cursor()
    cur.execute("""
        SELECT pp.selling_price::bigint, pp.units_per_box, pp.min_stock_level::bigint
        FROM pharmacy_products pp JOIN global_products gp ON gp.id = pp.global_product_id
        WHERE gp.barcode = %s
    """, (f"993{RUN}1",))
    row = cur.fetchone()
    check("صنف الواجهة: السعر 20 ج = 2000 قرش", row and row[0] == 2000, row)
    check("صنف الواجهة: 8 شرائط بالعلبة + حد 2", row and row[1] == 8 and row[2] == 2, row)
    cur.execute("""
        SELECT b.quantity, b.unit FROM inventory_batches b
        JOIN pharmacy_products pp ON pp.id = b.pharmacy_product_id
        JOIN global_products gp ON gp.id = pp.global_product_id
        WHERE gp.barcode = %s
    """, (f"993{RUN}1",))
    b = cur.fetchone()
    check("رصيد الواجهة: 3 علب × 8 = 24 شريط", b and b[0] == 24 and b[1] == "strip", b)
    cur.execute("""
        SELECT pp.selling_price::bigint FROM pharmacy_products pp
        JOIN global_products gp ON gp.id = pp.global_product_id WHERE gp.barcode = %s
    """, (f"993{RUN}2",))
    v = cur.fetchone()
    check("صنف كامل فقط: بيع كامل بلا سعر شريط", v and v[0] == 3500, v)
    conn.commit()
    conn.close()

    print(f"\n== {len(FAILURES) == 0 and 'ALL UI CHECKS PASSED' or str(len(FAILURES)) + ' FAILED'} ==")
    if FAILURES:
        print("FAILED:", FAILURES)
        sys.exit(1)


if __name__ == "__main__":
    main()
