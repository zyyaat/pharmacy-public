#!/usr/bin/env python3
"""E2E: Task 39 selling upgrades —
A) invoice discount (fixed amount, reflected in cart, message, API, and sales list)
B) deferred (آجل) sale for a named customer + customer account statement + payment
C) parked invoice (إيقاف مؤقت) with localStorage persistence across reload + resume
D) low-stock notification bell driven by the FULL-BOX rule:
   حد الطلب counts complete boxes only — leftover strips never count"""
import os
import sys
import time

import psycopg2
from playwright.sync_api import sync_playwright

APP = "http://localhost:3000"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"
DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable"
)

TEST_PRODUCT = f"منتج بيع مرن {int(time.time()) % 100000:05d}"
CUSTOMER_NAME = f"عميل آجل {int(time.time()) % 100000:05d}"

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


def wait_url(page, suffix, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if current_url(page).rstrip("/").endswith(suffix):
            return True
        time.sleep(0.2)
    return False


def add_to_cart(page, query):
    search_input = page.locator('input[role="combobox"]')
    search_input.wait_for(timeout=10000)
    search_input.click()
    search_input.fill("")
    page.keyboard.type(query, delay=40)
    options = page.locator('#pos-search-listbox [role="option"]')
    deadline = time.time() + 10
    while time.time() < deadline and options.count() == 0:
        time.sleep(0.2)
    options.first.click()


def api_get(page, path):
    return page.evaluate(
        """async (path) => {
            const r = await fetch(path, { credentials: 'include' });
            return await r.json();
        }""",
        path,
    )


def set_low_stock(product_name, level):
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE pharmacy_products pp SET min_stock_level = %s
                FROM global_products gp
                WHERE pp.global_product_id = gp.id AND gp.name = %s
                """,
                (level, product_name),
            )
        conn.commit()
    finally:
        conn.close()


def stock_full_boxes(product_name):
    """عدد العلب الكاملة المتاحة (تُهمل الشرائط المفردة) — نفس قاعدة الـ API."""
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT COALESCE(SUM(ci.quantity), 0)::int, GREATEST(COALESCE(pp.units_per_box, 1), 1)::int
                FROM pharmacy_products pp
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN current_inventory ci ON ci.pharmacy_product_id = pp.id
                WHERE gp.name = %s AND pp.is_active = true
                GROUP BY pp.id, pp.units_per_box
                ORDER BY pp.id
                LIMIT 1
                """,
                (product_name,),
            )
            row = cur.fetchone()
            return (row[0] // row[1]) if row else 0
    finally:
        conn.close()


def stock_shape(product_name):
    """(العلب الكاملة، الشرائط المتبقية) — الأساس يُقصّ عند الصفر مثل الـ API."""
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT COALESCE(SUM(ci.quantity), 0)::int, GREATEST(COALESCE(pp.units_per_box, 1), 1)::int
                FROM pharmacy_products pp
                JOIN global_products gp ON gp.id = pp.global_product_id
                LEFT JOIN current_inventory ci ON ci.pharmacy_product_id = pp.id
                WHERE gp.name = %s AND pp.is_active = true
                GROUP BY pp.id, pp.units_per_box
                ORDER BY pp.id
                LIMIT 1
                """,
                (product_name,),
            )
            row = cur.fetchone()
            if not row:
                return 0, 0
            base, upb = max(row[0], 0), row[1]
            return base // upb, base % upb
    finally:
        conn.close()


def box_word_ar(n):
    if n == 1:
        return 'علبة واحدة'
    if n == 2:
        return 'علبتين'
    if 3 <= n <= 10:
        return f'{n} علب'
    return f'{n} علبة'


def strip_word_ar(n):
    if n == 1:
        return 'شريط واحد'
    if n == 2:
        return 'شريطين'
    if 3 <= n <= 10:
        return f'{n} شرائط'
    return f'{n} شريط'


def availability_ar(full, strips):
    if full > 0 and strips > 0:
        return f'{full} علبة و{strip_word_ar(strips)}'
    if full > 0:
        return box_word_ar(full)
    return strip_word_ar(strips)


def deactivate_old_reference_products():
    """التشغيلات السابقة تترك منتجات مرجعية (بعضها نفد مخزونه يظهر أول الاقتراحات)
    — تُخفى من نقطة البيع حتى لا تلوث الاختبار."""
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE pharmacy_products pp SET is_active = false
                FROM global_products gp
                WHERE pp.global_product_id = gp.id AND gp.name LIKE 'منتج بيع مرن%'
                """,
            )
        conn.commit()
    finally:
        conn.close()


def main():
    deactivate_old_reference_products()
    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        page = ctx.new_page()

        # login
        page.goto(f"{APP}/login", wait_until="networkidle")
        page.fill('input[type="email"]', EMAIL)
        page.fill('input[type="password"]', PASSWORD)
        page.click('button[type="submit"]')
        deadline = time.time() + 20
        while time.time() < deadline and "/login" in current_url(page):
            time.sleep(0.2)
        check("تسجيل الدخول", "/login" not in current_url(page), current_url(page))

        # ---------- A0) create a fresh product with a known price (100 EGP) ----------
        page.goto(f"{APP}/inventory/new", wait_until="networkidle")
        page.wait_for_selector('text=بيانات العلاج', timeout=20000)
        barcode = f"{int(time.time() * 1000) % 10 ** 13:013d}"
        page.fill('input[name="name"]', TEST_PRODUCT)
        page.fill('input[name="barcode"]', barcode)
        page.fill('input[name="initial_boxes"]', "10")
        page.fill('input[name="cost_price"]', "60")
        page.fill('input[name="selling_price"]', "100")
        page.click('button:has-text("حفظ المنتج")')
        check("المنتج المرجعي أُنشئ (سعر معروف 100 جنيه)", wait_url(page, "/inventory"))

        # ---------- A) invoice discount (10 EGP → total 90 EGP) ----------
        page.goto(f"{APP}/pos", wait_until="networkidle")
        page.wait_for_selector('input[role="combobox"]', timeout=15000)
        add_to_cart(page, "منتج بيع مرن")
        total_before = page.locator('p.text-2xl').inner_text().strip()
        page.locator('input[aria-label="قيمة الخصم"]').fill("10")
        total_after = page.locator('p.text-2xl').inner_text().strip()
        check("الخصم يغيّر الإجمالي المعروض فوراً", total_before != total_after,
              f"{total_before} → {total_after}")
        page.click('button:has-text("إتمام البيع")')
        page.wait_for_selector('text=تم حفظ الفاتورة بنجاح', timeout=15000)
        message_text = page.locator('text=تم حفظ الفاتورة بنجاح').inner_text()
        check("رسالة النجاح تحمل الإجمالي بعد الخصم", total_after in message_text, message_text[:70])

        sales_data = api_get(page, "/api/v1/pharmacy/pos/sales?limit=3")["data"]["sales"]
        latest = sales_data[0]
        check("الخادم خزّن الخصم (1000 قرش) والإجمالي الصافي (9000)",
              latest["discount_amount_piastres"] == 1000 and latest["total_amount_piastres"] == 9000,
              f"discount={latest['discount_amount_piastres']} total={latest['total_amount_piastres']}")
        check("نوع الدفع الافتراضي نقدي", latest["payment_type"] == "cash")

        # ---------- B) deferred sale + customer account + payment ----------
        page.goto(f"{APP}/pos", wait_until="networkidle")
        page.wait_for_selector('input[role="combobox"]', timeout=15000)
        add_to_cart(page, "منتج بيع مرن")
        page.locator('button[role="combobox"][aria-label="طريقة الدفع"]').click()
        page.locator('div[role="option"]', has_text="آجل").first.click()
        page.locator('button:has-text("+ إضافة عميل جديد")').click()
        page.locator('input[aria-label="اسم العميل الجديد"]').fill(CUSTOMER_NAME)
        page.locator('input[aria-label="هاتف العميل الجديد"]').fill("01000000000")
        page.get_by_role("button", name="إضافة", exact=True).click()
        page.wait_for_selector(f'text={CUSTOMER_NAME}', timeout=10000)
        check("العميل الجديد اختير للبيع الآجل", page.locator(f'text={CUSTOMER_NAME}').count() >= 1)
        page.click('button:has-text("إتمام البيع الآجل")')
        page.wait_for_selector('text=تم تسجيل فاتورة آجل', timeout=15000)
        check("رسالة فاتورة الآجل تذكر اسم العميل", CUSTOMER_NAME in page.locator('text=تم تسجيل فاتورة آجل').inner_text())

        # sales history shows the credit badge + the discount chip
        page.goto(f"{APP}/sales", wait_until="networkidle")
        page.wait_for_selector('text=آجل', timeout=15000)
        check("سجل البيع يعرض شارة آجل مع اسم العميل",
              page.locator('text=آجل · ' + CUSTOMER_NAME).count() >= 1)
        sales_body = page.locator('body').inner_text()
        check("سجل البيع يعرض شارة الخصم", 'خصم' in sales_body and '١٠٫٠٠' in sales_body)

        # customers page: balance = invoice total (100 EGP = 10000 piastres)
        page.goto(f"{APP}/customers", wait_until="networkidle")
        page.wait_for_selector('text=العملاء', timeout=20000)
        page.locator('input[aria-label="بحث في العملاء"]').fill(CUSTOMER_NAME)
        page.wait_for_selector(f'text={CUSTOMER_NAME}', timeout=15000)
        row = page.locator('button', has_text=CUSTOMER_NAME).first
        row.click()
        page.wait_for_selector('text=فاتورة آجل', timeout=15000)
        statement = api_get(page, f"/api/v1/pharmacy/customers")["data"]["customers"]
        customer = next((c for c in statement if c["name"] == CUSTOMER_NAME), None)
        check("رصيد العميل يساوي فاتورة الآجل (10000 قرش)",
              customer is not None and customer["balance_piastres"] == 10000,
              f"balance={customer and customer['balance_piastres']}")
        check("الكشف يعرض فاتورة الآجل", page.locator('text=فاتورة آجل').count() >= 1)
        check("لا دفعات بعد", page.locator('text=سداد نقدي').count() == 0)

        # record a 50 EGP payment → balance halves
        page.locator('input[aria-label="مبلغ الدفعة بالجنيه"]').fill("50")
        page.locator('input[aria-label="ملاحظة الدفعة"]').fill("دفعة أولى")
        page.click('button:has-text("تسجيل الدفعة")')
        page.wait_for_selector('text=سداد نقدي', timeout=15000)
        statement_data = api_get(page, f"/api/v1/pharmacy/customers?search={CUSTOMER_NAME}")["data"]["customers"]
        check("الدفعة خفضت الرصيد إلى 5000 قرش",
              statement_data and statement_data[0]["balance_piastres"] == 5000,
              f"balance={statement_data and statement_data[0]['balance_piastres']}")
        check("الكشف يعرض سطر الدفعة", page.locator('text=دفعة أولى').count() >= 1)

        # ---------- B2) جرس الإشعارات يعرض ديون العملاء ----------
        page.goto(f"{APP}/pos", wait_until="networkidle")
        page.wait_for_selector('input[role="combobox"]', timeout=15000)
        bell = page.locator('button[title="الإشعارات"]')
        bell.click()
        page.wait_for_selector('text=ديون العملاء', timeout=10000)
        check("الجرس يعرض قسم «ديون العملاء»", page.locator('text=ديون العملاء').count() >= 1)
        check("الجرس يعرض العميل المدين باسمه", page.locator('a', has_text=CUSTOMER_NAME).count() >= 1,
              CUSTOMER_NAME)
        check("سطر الدين يعرض شارة «مدين» ورابط التحصيل",
              page.locator('text=مدين').count() >= 1 and page.locator('text=فتح حسابات العملاء للتحصيل').count() == 1)
        check("سطر الدين يذكر المبلغ المستحق", page.locator('text=مستحق عليه').count() >= 1)
        bell.click()

        # ---------- C) parked invoice: park → persist across reload → resume ----------
        page.goto(f"{APP}/pos", wait_until="networkidle")
        page.wait_for_selector('input[role="combobox"]', timeout=15000)
        add_to_cart(page, "منتج بيع مرن")
        page.click('button:has-text("إيقاف مؤقت")')
        page.wait_for_selector('text=فواتير معلّقة:', timeout=10000)
        check("الإيقاف المؤقت أفرغ السلة وخزّن الوسم",
              page.locator('text=لم تتم إضافة أصناف بعد').count() == 1 and page.locator('text=فواتير معلّقة:').count() == 1)
        page.reload(wait_until="networkidle")
        page.wait_for_selector('text=فواتير معلّقة:', timeout=20000)
        check("الفاتورة المعلقة صمدت بعد تحديث الصفحة", page.locator('text=فواتير معلّقة:').count() == 1)
        chip = page.locator('span.rounded-full', has_text='ج.م').first
        chip.locator('button').first.click()
        page.wait_for_selector('p.font-semibold', timeout=10000)
        line_visible = page.locator('p.font-semibold', has_text=TEST_PRODUCT).count() >= 1
        check("الاستئناف أعاد أصناف الفاتورة للسلة", line_visible)
        check("الاستئناف حذف الوسم من المعلّقة", page.locator('text=فواتير معلّقة:').count() == 0)

        # ---------- D) low-stock bell — FULL-BOX rule (حد الطلب بالعلبة الكاملة) ----------
        def wait_low_stock_api(page, product_name, present):
            deadline = time.time() + 15
            while time.time() < deadline:
                items = api_get(page, "/api/v1/pharmacy/inventory/low-stock")["data"]["items"]
                names = [i["product_name"] for i in items]
                if (product_name in names) == present:
                    return True
                time.sleep(0.3)
            return False

        full = stock_full_boxes("مرهم جروح")
        set_low_stock("مرهم جروح", full + 1)
        page.goto(f"{APP}/pos", wait_until="networkidle")
        page.wait_for_selector('input[role="combobox"]', timeout=15000)
        check("API يُدخل الصنف عندما العلب الكاملة < حد الطلب",
              wait_low_stock_api(page, "مرهم جروح", True), f"full_boxes={full}, min={full + 1}")
        bell = page.locator('button[title="الإشعارات"]')
        deadline = time.time() + 15
        badge_text = ""
        while time.time() < deadline:
            badge = bell.locator('span').first
            if badge.count() == 1:
                badge_text = badge.inner_text().strip()
                if badge_text:
                    break
            time.sleep(0.3)
        check("الجرس يعرض عدّاد التنبيهات (ديون + نواقص)", badge_text.isdigit() and int(badge_text) >= 1,
              f"badge={badge_text!r}")
        bell.click()
        page.wait_for_selector('text=المخزون المنخفض', timeout=10000)
        check("لوحة الجرس تعرض الصنف المنخفض", page.locator('text=مرهم جروح').count() >= 1)
        body_text = page.locator('body').inner_text()
        expected_qty = 'علبة واحدة' if full == 1 else ('علبتين' if full == 2 else str(full))
        check("الرسالة صريحة: تذكر المتبقي بالعلب الكاملة", expected_qty in body_text,
              f"expect {expected_qty!r}")
        check("الرسالة صريحة: تذكر حد الطلب", 'حد الطلب' in body_text)
        if full == 0:
            check("الشارة تُظهر «نفد» عند صفر علب كاملة", 'نفد' in body_text)
        else:
            check("الشارة تُظهر «منخفض»", 'منخفض' in body_text)
        check("اللوحة توفر رابط المخزون لاتخاذ الإجراء",
              page.locator('text=فتح صفحة المخزون لاتخاذ الإجراء').count() == 1)
        bell.click()

        # القاعدة الجوهرية: الشريط المفرد لا يُحسب — عند تساوي العلب الكاملة مع
        # حد الطلب يختفي التنبيه حتى لو تبقّت شرائط متناثرة في العلبة المفتوحة.
        set_low_stock("مرهم جروح", full)
        check("API يستبعد الصنف عندما العلب الكاملة = حد الطلب (الشرائط لا تُحسب)",
              wait_low_stock_api(page, "مرهم جروح", False), f"full_boxes={full}, min={full}")
        page.goto(f"{APP}/pos", wait_until="networkidle")
        page.wait_for_selector('input[role="combobox"]', timeout=15000)
        bell = page.locator('button[title="الإشعارات"]')
        bell.click()
        page.wait_for_selector('text=المخزون المنخفض', timeout=10000)
        check("اللوحة لم تعد تعرض الصنف بعد مساواة الحد بالعلب الكاملة",
              page.locator('text=مرهم جروح').count() == 0)
        bell.click()
        set_low_stock("مرهم جروح", 0)

        # الرسالة تعلن الشرائط المتبقية بوضوح — «نفد» لا تظهر ما دام على الرف شريط
        # (سيناريو المستخدم: الموجود شرائط والرسالة كانت تقول «نفذت الكمية»).
        for product_name in ("بانادول أدفانس", "بانادول اكسترا"):
            full, strips = stock_shape(product_name)
            set_low_stock(product_name, full + 1)
            check(f"API يُدخل {product_name} عندما الموجود أقل من الحد",
                  wait_low_stock_api(page, product_name, True),
                  f"full={full}, strips={strips}, min={full + 1}")
            page.goto(f"{APP}/pos", wait_until="networkidle")
            page.wait_for_selector('input[role="combobox"]', timeout=15000)
            bell = page.locator('button[title="الإشعارات"]')
            bell.click()
            page.wait_for_selector('text=المخزون المنخفض', timeout=10000)
            row_text = page.locator('a', has_text=product_name).first.inner_text()
            expected = f"حد الطلب {box_word_ar(full + 1)} · الموجود {availability_ar(full, strips)}"
            check(f"رسالة {product_name} تعلن الحد والموجود بوضوح", expected in row_text,
                  f"expect={expected!r} got={row_text!r}")
            check(f"{product_name} لا تظهر عليه «نفد» ما دامت هناك كمية",
                  'نفد' not in row_text and 'منخفض' in row_text, row_text)
            bell.click()
            set_low_stock(product_name, 0)

        browser.close()

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {FAILURES}")
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
