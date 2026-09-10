#!/usr/bin/env python3
"""E2E شامل لنظام الصلاحيات المرن (Task 42).

السيناريو (يحتاج backend:8080 + frontend:3000 + DB):
  1) المالك يفتح تبويب الموظفين — يرى زر «إضافة موظف جديد»
  2) يضيف موظفًا بقالب «كاشير» عبر الواجهة
  3) تسجيل خروج ثم دخول بحساب الموظف — القائمة الجانبية مخفف بالصلاحيات
  4) الموظف لا يرى التقارير/الموظفين في القائمة ويحصل 403 من الـ API
  5) المالك يعدّل صلاحيات الموظف ويضيف reports.sales — تظهر فورًا
  6) إيقاف الموظف ثم التحقق من منع دخوله
"""
import sys
import time
import requests

BASE = "http://127.0.0.1:8080/api/v1"
APP = "http://localhost:3000"
OWNER = ("print-test@test.io", "Str0ng!Pass2026")
STAFF = ("staff-perms@test.io", "Staff!Perm2026")

checks = []


def check(name, ok, detail=""):
    checks.append(ok)
    print(("PASS " if ok else "FAIL ") + name + (f" — {detail}" if detail and not ok else ""))
    return ok


def csrf_header(session):
    token = session.cookies.get("pharmacy_csrf")
    return {"X-CSRF-Token": token} if token else {}


def owner_session():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": OWNER[0], "password": OWNER[1]}, timeout=10)
    return s, r.status_code


def employee_api_session():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": STAFF[0], "password": STAFF[1]}, timeout=10)
    return s, r.status_code


def cleanup_staff():
    import psycopg2
    conn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("DELETE FROM employee_permissions WHERE employee_id IN (SELECT id FROM employees WHERE email=%s)", (STAFF[0],))
    cur.execute("DELETE FROM auth_sessions WHERE principal_type='employee' AND principal_id::uuid IN (SELECT id FROM employees WHERE email=%s)", (STAFF[0],))
    cur.execute("DELETE FROM employees WHERE email=%s", (STAFF[0],))
    conn.close()


def main():
    from playwright.sync_api import sync_playwright

    cleanup_staff()

    # ============ 1) المالك: تبويب الموظفين عبر المتصفح ============
    with sync_playwright() as p:
        browser = p.chromium.launch()
        owner_page = browser.new_page()

        owner_page.goto(f"{APP}/login", wait_until="networkidle")
        owner_page.fill('input[type="email"]', OWNER[0])
        owner_page.fill('input[type="password"]', OWNER[1])
        owner_page.click('button[type="submit"]')
        owner_page.wait_for_url(lambda url: not url.endswith("/login"), timeout=30000)

        owner_page.goto(f"{APP}/employees", wait_until="networkidle")
        time.sleep(1.0)
        content = owner_page.content()
        check("1a. صفحة الموظفين تفتح للمالك", "الموظفون" in content)
        check("1b. زر إضافة موظف جديد ظاهر للمالك", "إضافة موظف جديد" in content)

        # ============ 2) إضافة موظف بقالب كاشير عبر الواجهة ============
        owner_page.click("text=إضافة موظف جديد")
        time.sleep(0.8)
        check("2a. نافذة الإضافة فتحت", owner_page.locator("text=تفاصيل الصلاحيات").count() > 0)

        owner_page.fill('input[placeholder="مثال: منى"]', "سعيد")
        owner_page.fill('input[placeholder="مثال: عبد الله"]', "الجندي")
        owner_page.fill('input[placeholder="staff@pharmacy.com"]', STAFF[0])
        owner_page.fill('input[placeholder="••••••••"]', STAFF[1])

        # اختيار قالب الكاشير
        owner_page.click("div.fixed >> text=كاشير")
        time.sleep(0.5)
        check("2b. قالب الكاشير مُطبّق (9 صلاحيات)", owner_page.locator("text=(9 مفعّلة)").count() > 0)

        owner_page.click("text=حفظ الموظف")
        time.sleep(1.5)
        content = owner_page.content()
        check("2c. الموظف أُضيف ويظهر بالقائمة", "سعيد الجندي" in content or "سعيد" in content)

        # ============ 2-د) المالك مرجع الإخفاء: يرى كل الأزرار ============
        owner_page.goto(f"{APP}/customers", wait_until="networkidle")
        time.sleep(1.5)
        check("2e. المالك يرى زر «عميل جديد»", "عميل جديد" in owner_page.content())
        # إضافة عميل عبر الواجهة → يُحدد تلقائيًا → كشف حسابه يفتح وصندوق الدفعات يظهر
        def wait_for_text(needle, timeout=10.0):
            deadline = time.time() + timeout
            while time.time() < deadline:
                if needle in owner_page.content():
                    return True
                time.sleep(0.3)
            return False

        owner_page.click("text=عميل جديد")
        time.sleep(0.5)
        owner_page.fill('input[aria-label="اسم العميل الجديد"]', "عميل فحص الإخفاء")
        owner_page.click('button:text-is("إضافة")')
        check("2d. المالك يرى «تسجيل دفعة سداد» بعد تحديد عميل", wait_for_text("تسجيل دفعة سداد"))
        owner_page.goto(f"{APP}/inventory", wait_until="networkidle")
        time.sleep(1.5)
        content = owner_page.content()
        check("2f. المالك يرى «إضافة منتج» بالمخزون", "إضافة منتج" in content)
        check("2g. المالك يرى أزرار الإجراءات (تعديل/مخزون)", "الإجراءات" in content)

        # جلسة مالك للـ API (تُستخدم لاحقًا في المنح والإيقاف)
        s, status = owner_session()
        check("5a. جلسة مالك للـ API", status == 200)
        r = s.get(f"{BASE}/pharmacy/employees", timeout=10)
        staff = next((e for e in r.json()["data"] if e["email"] == STAFF[0]), None)
        check("5b. الموظف موجود في قائمة API", staff is not None)
        eid = staff["id"]

        # ============ 3) دخول الموظف: القائمة مخففة ============
        staff_page = browser.new_page()
        staff_page.goto(f"{APP}/login", wait_until="networkidle")
        staff_page.fill('input[type="email"]', STAFF[0])
        staff_page.fill('input[type="password"]', STAFF[1])
        staff_page.click('button[type="submit"]')
        staff_page.wait_for_url(lambda url: not url.endswith("/login"), timeout=30000)
        time.sleep(2.0)

        sidebar_text = staff_page.locator("aside").inner_text()
        check("3a. الموظف لا يرى «التقارير» في القائمة", "التقارير" not in sidebar_text, sidebar_text)
        check("3b. الموظف لا يرى «الموظفون» في القائمة", "الموظفون" not in sidebar_text)
        check("3c. الموظف يرى «نقطة البيع»", "نقطة البيع" in sidebar_text, sidebar_text)

        # ============ 3-د) Task 43: لوحة التحكم بدون أزرار ممنوعة ============
        # ⚠️ Task 48: نصوص الكتالوج مدمجة في حمولة RSC داخل content() — نتحقق من النص المرئي فقط
        time.sleep(1.0)
        dash = staff_page.locator("body").inner_text()
        check("3d. لوحة الموظف بلا «إضافة منتج»", "إضافة منتج" not in dash)
        check("3e. الإجراءات السريعة بلا «الموظفون»", "الموظفون" not in dash)
        check("3f. الإجراءات السريعة بلا «التقارير»", "التقارير" not in dash)

        # ============ 3-هـ) صفحة العملاء: الدفعات مخفية والإضافة ظاهرة ============
        staff_page.goto(f"{APP}/customers", wait_until="networkidle")
        time.sleep(1.5)
        cust = staff_page.content()
        check("3h. الكاشير يرى زر «عميل جديد» (عنده customers.create)", "عميل جديد" in cust)
        # نضيف عميلًا ليُحدد تلقائيًا — بذلك نفحص صندوق الدفعات وهو ظاهر فعلًا بالصفحة
        def wait_staff_text(needle, timeout=10.0):
            deadline = time.time() + timeout
            while time.time() < deadline:
                if needle in staff_page.content():
                    return True
                time.sleep(0.3)
            return False

        staff_page.click("text=عميل جديد")
        time.sleep(0.5)
        staff_page.fill('input[aria-label="اسم العميل الجديد"]', "عميل الكاشير فحص")
        staff_page.click('button:text-is("إضافة")')
        selected_loaded = wait_staff_text("لا حركات بعد")
        cust = staff_page.locator("body").inner_text()
        check("3g. الكاشير (بلا customers.payments): لا «تسجيل دفعة سداد» حتى مع عميل محدد",
              selected_loaded and "تسجيل دفعة سداد" not in cust, f"selected_loaded={selected_loaded}")

        # ============ 3-و) صفحة المخزون: أزرار التعديل مخفية ============
        staff_page.goto(f"{APP}/inventory", wait_until="networkidle")
        time.sleep(1.8)
        inv = staff_page.locator("body").inner_text()
        check("3i. الكاشير لا يرى «إضافة منتج»", "إضافة منتج" not in inv)
        check("3j. الكاشير يرى «فتح نقطة البيع» (عنده pos.access)", "فتح نقطة البيع" in inv)
        check("3k. عمود الإجراءات مخفي كليًا", "الإجراءات" not in inv)
        check("3l. لا زر تعديل منتج", "تعديل بيانات المنتج" not in inv)

        # ============ 3-ز) المسارات الممنوعة المكتوبة يدويًا → بطاقة غير متاحة ============
        def wait_for_text(page, needle, timeout=10.0):
            deadline = time.time() + timeout
            while time.time() < deadline:
                if needle in page.content():
                    return True
                time.sleep(0.3)
            return False

        for guarded in ["/reports", "/employees", "/inventory/movements", "/attendance"]:
            staff_page.goto(f"{APP}{guarded}", wait_until="networkidle")
            blocked = wait_for_text(staff_page, "غير متاحة لحسابك")
            check(f"3m. {guarded} محمية (بطاقة غير متاحة)", blocked)

        # ============ 3-ح) الإعدادات: قسم الفواتير فقط ============
        staff_page.goto(f"{APP}/settings", wait_until="networkidle")
        time.sleep(2.5)
        settings_url = staff_page.evaluate("window.location.href")
        check("3n. مدخل الإعدادات حوّل لأول قسم مسموح (receipts)", "/settings/receipts" in settings_url, settings_url)
        st = staff_page.locator("body").inner_text()
        check("3o. الكاشير يرى «الفواتير والطباعة» و«اللغة» فقط (اللغة لكل الحسابات — Task 48)",
              "الفواتير والطباعة" in st and "اللغة" in st
              and "ترحيل المنتجات" not in st and "قاعدة البيانات" not in st)

        # ============ 4) الـ API يرفض الأقسام غير المصرح بها ============
        es, estatus = employee_api_session()
        check("4a. دخول الموظف للـ API", estatus == 200)
        check("4b. API يمنع التقارير (403)", es.get(f"{BASE}/pharmacy/reports/sales", timeout=10).status_code == 403)
        check("4c. API يمنع الموظفين (403)", es.get(f"{BASE}/pharmacy/employees", timeout=10).status_code == 403)
        check("4d. API يسمح بنقطة البيع (200)", es.get(f"{BASE}/pharmacy/pos/search?q=%D8%A8%D8%A7%D9%86", timeout=10).status_code == 200)
        r = es.get(f"{BASE}/pharmacy/permissions/me", timeout=10)
        me = r.json()
        check("4e. me للمرتجعات صحيح", me.get("full_access") is False and len(me.get("permissions", [])) == 9, str(me)[:150])

        # سجل الترحيلات (Task 44): بيانات بنية تحتية — للمالك فقط حتى في الـ API
        r = es.get(f"{BASE}/pharmacy/system/migrations", timeout=10)
        check("4f. سجل الترحيلات ممنوع على الموظف (403 OWNER_ONLY)",
              r.status_code == 403 and r.json().get("code") == "OWNER_ONLY", f"{r.status_code} {r.text[:80]}")
        check("4g. سجل الترحيلات متاح للمالك (200)",
              s.get(f"{BASE}/pharmacy/system/migrations", timeout=10).status_code == 200)

        # ============ 5-ج) المالك يمنح reports.sales ثم يُسمح بالتقرير ============
        r = s.put(f"{BASE}/pharmacy/employees/{eid}/permissions", headers=csrf_header(s),
                  json={"permissions": [
                      "dashboard.view", "pos.access", "sales.view", "inventory.view",
                      "customers.view", "customers.create", "branches.view",
                      "attendance.clock_in_out", "settings.receipts", "reports.sales"]}, timeout=10)
        check("5c. المالك أضاف reports.sales عبر التبويبات", r.status_code == 200)

        # ============ 5-د) بعد منح reports.sales يفتح التقرير ============
        check("5d. API يفتح تقارير المبيعات بعد المنح (200)", es.get(f"{BASE}/pharmacy/reports/sales", timeout=10).status_code == 200)

        # ============ 5-هـ) Task 43: المنح الفوري يظهر بطاقة التقرير في الواجهة ============
        staff_page.goto(f"{APP}/reports", wait_until="networkidle")
        time.sleep(2.0)
        rep = staff_page.locator("body").inner_text()
        check("5e. بعد المنح: تقرير المبيعات ظهر كبطاقة (لا بطاقة رفض)", "تقرير المبيعات" in rep and "غير متاحة لحسابك" not in rep)

        # ============ 6) إيقاف الموظف يمنع دخوله ============
        r = s.patch(f"{BASE}/pharmacy/employees/{eid}/status", headers=csrf_header(s), json={"status": "inactive"}, timeout=10)
        check("6a. إيقاف الموظف", r.status_code == 200)
        check("6b. جلسة الموظف القديمة قُطعت (401)", es.get(f"{BASE}/pharmacy/pos/search?q=x", timeout=10).status_code == 401)
        _, estatus2 = employee_api_session()
        check("6c. الدخول مرفوض بعد الإيقاف", estatus2 in (401, 403))
        r = s.patch(f"{BASE}/pharmacy/employees/{eid}/status", headers=csrf_header(s), json={"status": "active"}, timeout=10)
        check("6d. إعادة التفعيل", r.status_code == 200)
        _, estatus3 = employee_api_session()
        check("6e. الدخول يعمل بعد التفعيل", estatus3 == 200)

        browser.close()

    failed = checks.count(False)
    print(f"\n==== {len(checks) - failed}/{len(checks)} checks passed ====")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
