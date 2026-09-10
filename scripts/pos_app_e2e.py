#!/usr/bin/env python3
"""E2E لتطبيق نقطة البيع المستقل (pos-app على المنفذ 3001).

السيناريو (يحتاج backend:8080 + pos-app:3001 + DB):
  1) المالك يسجل الدخول على التطبيق الجديد ويُحول تلقائيًا إلى /pos
  2) قائمته الجانبية: نقطة البيع + سجل البيع فقط (نفس منطق الصلاحيات)
  3) بيع كامل: بحث → سلة → إتمام → إيصال يطبع من التطبيق الجديد
  4) سجل البيع يعرض الفاتورة للمالك
  5) موظف مقيّد (pos.access + customers.create فقط): يرى نقطة البيع فقط
  6) /sales بالرابط المباشر → بطاقة «غير متاحة» + الـ API يمنع (403) ويسمح للبيع
  7) تطبيق الإدارة على 3000 لم يتأثر
"""
import sys
import time

import requests

BASE = "http://127.0.0.1:8080/api/v1"
POS_APP = "http://localhost:3001"
MAIN_APP = "http://localhost:3000"
OWNER = ("print-test@test.io", "Str0ng!Pass2026")
STAFF = ("pos-only@test.io", "PosOnly!2026")

checks = []


def check(name, ok, detail=""):
    checks.append(ok)
    print(("PASS " if ok else "FAIL ") + name + (f" — {detail}" if detail and not ok else ""))
    return ok


def csrf_header(session):
    token = session.cookies.get("pharmacy_csrf")
    return {"X-CSRF-Token": token} if token else {}


def current_url(page):
    try:
        return page.evaluate("window.location.href")
    except Exception:
        return page.url


def cleanup_staff():
    import psycopg2
    conn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("DELETE FROM employee_permissions WHERE employee_id IN (SELECT id FROM employees WHERE email=%s)", (STAFF[0],))
    cur.execute("DELETE FROM auth_sessions WHERE principal_type='employee' AND principal_id::uuid IN (SELECT id FROM employees WHERE email=%s)", (STAFF[0],))
    cur.execute("DELETE FROM employees WHERE email=%s", (STAFF[0],))
    conn.close()


def owner_api_session():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": OWNER[0], "password": OWNER[1]}, timeout=10)
    return s, r.status_code


STUB_PRINT_JS = """() => {
    window.__prints = 0
    window.print = () => {
        window.__prints += 1
        window.__receiptHTML = document.getElementById('receipt-print-host')?.innerHTML || ''
    }
}"""


def wait_options(locator, timeout=8.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if locator.count() > 0:
            return True
        time.sleep(0.2)
    return False


def complete_sale_and_print(page, query):
    """بحث → إضافة للسلة → إتمام البيع → طباعة (يدوية أو تلقائية حسب الإعدادات)"""
    search_input = page.locator('input[role="combobox"]')
    search_input.wait_for(timeout=15000)
    page.evaluate(STUB_PRINT_JS)
    search_input.click()
    search_input.fill("")
    page.keyboard.type(query, delay=50)
    options = page.locator('#pos-search-listbox [role="option"]')
    if not wait_options(options):
        return None
    options.first.click()
    page.click('button:has-text("إتمام البيع")')
    # الوضع التلقائي يطبع فورًا؛ اليدوي يعرض زر طباعة
    deadline = time.time() + 10
    while time.time() < deadline:
        if page.evaluate("window.__prints") == 1:
            return page.evaluate("window.__receiptHTML || ''")
        if page.locator('button:has-text("طباعة الفاتورة")').count() > 0:
            page.click('button:has-text("طباعة الفاتورة")')
            page.wait_for_timeout(900)
            return page.evaluate("window.__receiptHTML || ''")
        time.sleep(0.3)
    return None


def main():
    from playwright.sync_api import sync_playwright

    cleanup_staff()

    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        page = ctx.new_page()

        # ============ 1) المالك: دخول وتحويل تلقائي لنقطة البيع ============
        page.goto(f"{POS_APP}/login", wait_until="networkidle")
        check("1a. صفحة دخول نقطة البيع تفتح", "تسجيل الدخول" in page.content())
        page.fill('input[type="email"]', OWNER[0])
        page.fill('input[type="password"]', OWNER[1])
        page.click('button[type="submit"]')
        deadline = time.time() + 25
        while time.time() < deadline and "/pos" not in current_url(page):
            time.sleep(0.25)
        check("1b. التحويل التلقائي إلى /pos بعد الدخول", "/pos" in current_url(page), current_url(page))

        # ============ 2) قائمة المالك: القسمان فقط ============
        time.sleep(1.5)
        sidebar = page.locator("aside").inner_text()
        check("2a. المالك يرى «نقطة البيع»", "نقطة البيع" in sidebar, sidebar[:100])
        check("2b. المالك يرى «سجل البيع»", "سجل البيع" in sidebar)
        check("2c. لا مخزون/موظفين/تقارير في قائمة POS", "المخزون" not in sidebar and "الموظفون" not in sidebar and "التقارير" not in sidebar)

        # ============ 3) بيع كامل + إيصال من التطبيق الجديد ============
        receipt = complete_sale_and_print(page, "كاربيما")
        check("3a. بيع كامل تم (بحث + سلة + إتمام)", receipt is not None)
        check("3b. الإيصال يطبع بمحتواه الصحيح", receipt is not None and "فاتورة رقم" in receipt and "كاربيمازول" in receipt,
              (receipt or "")[:120])

        # ============ 4) سجل البيع للمالك ============
        page.goto(f"{POS_APP}/sales", wait_until="networkidle")
        blocked_wait = time.time() + 8
        while time.time() < blocked_wait and "لا توجد فواتير بعد" in page.content():
            time.sleep(0.3)
        content = page.content()
        check("4a. سجل البيع يفتح ويعرض كروت الفواتير للمالك",
              "INV-" in content and "لا توجد فواتير بعد" not in content)

        # ============ 5) موظف مقيّد: pos.access + customers.create فقط ============
        s, status = owner_api_session()
        check("5a. جلسة مالك للـ API", status == 200)
        r = s.post(f"{BASE}/pharmacy/employees", headers=csrf_header(s),
                   json={"first_name": "كاشير", "last_name": "نقطة البيع", "email": STAFF[0],
                         "password": STAFF[1], "permissions": ["pos.access", "customers.create"]},
                   timeout=10)
        check("5b. إنشاء موظف POS فقط عبر API", r.status_code in (200, 201), r.text[:120])

        staff_page = browser.new_page()
        staff_page.goto(f"{POS_APP}/login", wait_until="networkidle")
        staff_page.fill('input[type="email"]', STAFF[0])
        staff_page.fill('input[type="password"]', STAFF[1])
        staff_page.click('button[type="submit"]')
        deadline = time.time() + 25
        while time.time() < deadline and "/pos" not in current_url(staff_page):
            time.sleep(0.25)
        check("5c. الموظف يصل نقطة البيع بعد دخوله", "/pos" in current_url(staff_page), current_url(staff_page))
        time.sleep(1.5)
        staff_sidebar = staff_page.locator("aside").inner_text()
        check("5d. الموظف يرى «نقطة البيع» فقط — «سجل البيع» مخفي",
              "نقطة البيع" in staff_sidebar and "سجل البيع" not in staff_sidebar, staff_sidebar[:100])

        # ============ 6) المسار الممنوع + الفرض في الـ API ============
        staff_page.goto(f"{POS_APP}/sales", wait_until="networkidle")
        blocked = False
        deadline = time.time() + 10
        while time.time() < deadline:
            if "غير متاحة لحسابك" in staff_page.content():
                blocked = True
                break
            time.sleep(0.3)
        check("6a. /sales بالرابط المباشر → بطاقة «غير متاحة لحسابك»", blocked)

        es = requests.Session()
        estatus = es.post(f"{BASE}/auth/pharmacy/login", json={"email": STAFF[0], "password": STAFF[1]}, timeout=10).status_code
        check("6b. دخول الموظف للـ API", estatus == 200)
        check("6c. API يسمح بحث نقطة البيع للموظف (200)",
              es.get(f"{BASE}/pharmacy/pos/search?q=%D8%A8%D8%A7%D9%86", timeout=10).status_code == 200)
        check("6d. API يمنع سجل البيع عن الموظف (403)",
              es.get(f"{BASE}/pharmacy/pos/sales", timeout=10).status_code == 403)

        # نقطة البيع تظل تعمل للموظف فعلًا
        staff_page.goto(f"{POS_APP}/pos", wait_until="networkidle")
        si = staff_page.locator('input[role="combobox"]')
        si.wait_for(timeout=15000)
        si.click()
        si.fill("")
        staff_page.keyboard.type("بانادول", delay=50)
        opts = staff_page.locator('#pos-search-listbox [role="option"]')
        check("6e. الموظف يبيع فعلًا في نقطة البيع (اقتراحات ظهرت)", wait_options(opts))

        # ============ 7) التطبيق الرئيسي لم يتأثر ============
        r = requests.get(f"{MAIN_APP}/login", timeout=15)
        check("7a. تطبيق الإدارة على 3000 سليم", r.status_code == 200)

        browser.close()

    failed = checks.count(False)
    print(f"\n==== {len(checks) - failed}/{len(checks)} checks passed ====")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
