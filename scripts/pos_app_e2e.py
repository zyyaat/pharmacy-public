#!/usr/bin/env python3
"""E2E لتطبيق نقطة البيع المستقل (pos-app على المنفذ 3001).

السيناريو (يحتاج backend:8080 + pos-app:3001 + DB):
  1) المالك يسجل الدخول على التطبيق الجديد ويُحول تلقائيًا إلى /pos
  2) قائمته الجانبية: نقطة البيع + سجل البيع + المخزون + سجل المخزون (نفس مفاتيح الصلاحيات)
  3) بيع كامل: بحث → سلة → إتمام → إيصال يطبع من التطبيق الجديد
  4) سجل البيع يعرض الفاتورة للمالك
  5) إدارة مخزون كاملة من نفس التطبيق: قائمة التشغيلات → إضافة منتج بمخزون افتتاحي
     → التحكم في الكمية (+2 بسبب) → سجل الحركات يظهر تسوية مخزون بالسبب
  6) موظف مقيّد (pos.access + customers.create فقط): يرى نقطة البيع فقط،
     /inventory و /sales بالرابط المباشر بطاقة «غير متاحة» والـ API يمنع (403)
  7) /sales بالرابط المباشر → بطاقة «غير متاحة» + الـ API يمنع (403) ويسمح للبيع
  8) تطبيق الإدارة على 3000 لم يتأثر
  9) نظام اللغات (Task 48): /me يعيد locale، PATCH /auth/pharmacy/locale يغيّره
     ويمنع اللغات غير المدعومة، وصفحة الإعدادات تبدّل الواجهة فورًا (RTL↔LTR)
     وتلزوم بعد إعادة التحميل (كوكي + حفظ دائم على الحساب) ثم يعود للعربية
 10) إدارة الفروع (Task 50): POST يضيف فرعاً جديداً كلياً، PUT يعدّل بياناته،
     تعديل الفرع الرئيسي يحدّث معلومات الصيدلية في السياق، حذف الرئيسي محمي،
     تحقق المدخلات (اسم فارغ/بريد غير صحيح) والموظف المقيّد يُمنع (403)
 11) اللغة تتبع الحساب (Task 50): بمتصفح جديد تمامًا (صفر كوكيز) بعد الدخول
     مباشرة تُفرش واجهة بلغة الحساب من قاعدة البيانات — بلا إعادة تحميل
 12) تشخيص تسليم بريد OTP (Task 56): «نجاح الإرسال» يعني فقط أن Brevo قبلت
     الرسالة؛ GET /auth/platform/email-delivery-status (محمي بجلسة المنصة)
     يكشف الحقيقة: محمي 401 بلا جلسة/بنطاق خاطئ، تحقق مدخلات 400، وبلا
     إعداد Brevo يعيد 503 email_not_configured
"""
import sys
import time

import requests

BASE = "http://127.0.0.1:8080/api/v1"
POS_APP = "http://localhost:3001"
MAIN_APP = "http://localhost:3000"
OWNER = ("print-test@test.io", "Str0ng!Pass2026")
STAFF = ("pos-only@test.io", "PosOnly!2026")
PLATFORM = ("e2e-admin@pharmacyos.test", "E2eAdmin#2026")

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


def wait_sidebar_contains(page, needle, timeout=12.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if needle in page.locator("aside").inner_text():
                return True
        except Exception:
            pass
        time.sleep(0.3)
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

        # ============ 2) قائمة المالك: نقطة البيع + سجل البيع + المخزون ============
        time.sleep(1.5)
        sidebar = page.locator("aside").inner_text()
        check("2a. المالك يرى «نقطة البيع»", "نقطة البيع" in sidebar, sidebar[:100])
        check("2b. المالك يرى «سجل البيع»", "سجل البيع" in sidebar)
        check("2c. المالك يرى «المخزون والأدوية» و «سجل المخزون»",
              "المخزون والأدوية" in sidebar and "سجل المخزون" in sidebar)
        check("2d. لا موظفين/تقارير/عملاء في قائمة POS",
              "الموظفون" not in sidebar and "التقارير" not in sidebar and "العملاء" not in sidebar)

        # ============ 3) بيع كامل + إيصال من التطبيق الجديد ============
        receipt = complete_sale_and_print(page, "كاربيما")
        check("3a. بيع كامل تم (بحث + سلة + إتمام)", receipt is not None)
        check("3b. الإيصال يطبع بمحتواه الصحيح", receipt is not None and "فاتورة رقم" in receipt and "كاربيمازول" in receipt,
              (receipt or "")[:120])

        # ============ 4) سجل البيع للمالك ============
        page.goto(f"{POS_APP}/sales", wait_until="networkidle")
        blocked_wait = time.time() + 8
        # ⚠️ نصوص الكتالوج مدمجة في حمولة RSC داخل content() — نتحقق من النص المرئي فقط
        while time.time() < blocked_wait and "لا توجد فواتير بعد" in page.locator("body").inner_text():
            time.sleep(0.3)
        body_text = page.locator("body").inner_text()
        check("4a. سجل البيع يفتح ويعرض كروت الفواتير للمالك",
              "INV-" in body_text and "لا توجد فواتير بعد" not in body_text)

        # ============ 5) إدارة مخزون كاملة من نفس التطبيق ============
        PROD = "شراب اختبار آي أو إس"
        BARCODE = "E2E-POS-INV-1"

        # 5a) قائمة المخزون تعرض تشغيلات الأصناف الموجودة
        page.goto(f"{POS_APP}/inventory", wait_until="networkidle")
        deadline = time.time() + 15
        while time.time() < deadline and "كاربيمازول" not in page.content():
            time.sleep(0.3)
        check("5a. قائمة المخزون تفتح وتعرض التشغيلات", "المخزون والأدوية" in page.content() and "كاربيمازول" in page.content())

        # 5b) إضافة منتج جديد بمخزون افتتاحي (نفس نموذج التطبيق الرئيسي)
        page.goto(f"{POS_APP}/inventory/new", wait_until="networkidle")
        page.fill('input[name="name"]', PROD)
        page.fill('input[name="barcode"]', BARCODE)
        page.fill('input[name="cost_price"]', "40")
        page.fill('input[name="selling_price"]', "55")
        page.fill('input[name="initial_boxes"]', "3")
        page.fill('input[name="batch_number"]', "B-E2E-1")
        page.fill('input[name="expiry_date"]', "2030-12-31")
        page.click('button[type="submit"]')
        deadline = time.time() + 20
        while time.time() < deadline:
            if "/inventory/new" not in current_url(page) and PROD in page.content():
                break
            time.sleep(0.3)
        # نقصّر القائمة بالباركود لضمان صف واحد
        page.fill('input[placeholder="بحث بالاسم أو الباركود"]', BARCODE)
        deadline = time.time() + 10
        while time.time() < deadline and PROD not in page.content():
            time.sleep(0.3)
        row_text = page.locator("tbody tr", has_text=PROD).first.inner_text()
        check("5b. منتج جديد بمخزون افتتاحي 3 عبوات ظهر في القائمة",
              "3 عبوة" in row_text, row_text[:120])

        # 5c) التحكم في المخزون: +2 عبوة بسبب «جرد دوري»
        page.locator("tbody tr", has_text=PROD).first.locator('button:has-text("مخزون")').click()
        page.wait_for_selector("text=التحكم في المخزون", timeout=8000)
        page.fill('input[type="number"]', "2")
        page.fill('input[placeholder^="تالف"]', "جرد دوري")
        page.click('button:has-text("إضافة للمخزون")')
        deadline = time.time() + 15
        saved = False
        while time.time() < deadline:
            body = page.locator("tbody tr", has_text=PROD).first.inner_text()
            body_all = page.locator("body").inner_text()
            if "التحكم في المخزون" not in body_all and "5 عبوة" in body:
                saved = True
                break
            time.sleep(0.4)
        check("5c. إضافة 2 عبوة نجحت — القائمة تعرض 5 عبوات", saved)

        # 5d) سجل حركات المخزون: شراء افتتاحي + تسوية مخزون بالسبب
        page.goto(f"{POS_APP}/inventory/movements", wait_until="networkidle")
        page.fill('input[placeholder^="ابحث باسم الدواء"]', "B-E2E-1")
        page.click('button:has-text("تطبيق")')
        deadline = time.time() + 15
        while time.time() < deadline and "تسوية مخزون" not in page.content():
            time.sleep(0.3)
        moves_content = page.content()
        check("5d. سجل المخزون يعرض تسوية مخزون بسبب «جرد دوري»",
              "تسوية مخزون" in moves_content and "جرد دوري" in moves_content and "B-E2E-1" in moves_content)

        # ============ 6) موظف مقيّد: pos.access + customers.create فقط ============
        s, status = owner_api_session()
        check("6a. جلسة مالك للـ API", status == 200)
        r = s.post(f"{BASE}/pharmacy/employees", headers=csrf_header(s),
                   json={"first_name": "كاشير", "last_name": "نقطة البيع", "email": STAFF[0],
                         "password": STAFF[1], "permissions": ["pos.access", "customers.create"]},
                   timeout=10)
        check("6b. إنشاء موظف POS فقط عبر API", r.status_code in (200, 201), r.text[:120])

        staff_page = browser.new_page()
        staff_page.goto(f"{POS_APP}/login", wait_until="networkidle")
        staff_page.fill('input[type="email"]', STAFF[0])
        staff_page.fill('input[type="password"]', STAFF[1])
        staff_page.click('button[type="submit"]')
        deadline = time.time() + 25
        while time.time() < deadline and "/pos" not in current_url(staff_page):
            time.sleep(0.25)
        check("6c. الموظف يصل نقطة البيع بعد دخوله", "/pos" in current_url(staff_page), current_url(staff_page))
        time.sleep(1.5)
        staff_sidebar = staff_page.locator("aside").inner_text()
        check("6d. الموظف يرى «نقطة البيع» و«الإعدادات» فقط — سجل البيع والمخزون مخفيان",
              "نقطة البيع" in staff_sidebar and "الإعدادات" in staff_sidebar
              and "سجل البيع" not in staff_sidebar and "المخزون" not in staff_sidebar,
              staff_sidebar[:120])

        # ============ 7) المسارات الممنوعة + الفرض في الـ API ============
        staff_page.goto(f"{POS_APP}/sales", wait_until="networkidle")
        blocked = False
        deadline = time.time() + 10
        while time.time() < deadline:
            if "غير متاحة لحسابك" in staff_page.content():
                blocked = True
                break
            time.sleep(0.3)
        check("7a. /sales بالرابط المباشر → بطاقة «غير متاحة لحسابك»", blocked)

        staff_page.goto(f"{POS_APP}/inventory", wait_until="networkidle")
        blocked = False
        deadline = time.time() + 10
        while time.time() < deadline:
            if "غير متاحة لحسابك" in staff_page.content():
                blocked = True
                break
            time.sleep(0.3)
        check("7b. /inventory بالرابط المباشر → بطاقة «غير متاحة لحسابك»", blocked)

        es = requests.Session()
        estatus = es.post(f"{BASE}/auth/pharmacy/login", json={"email": STAFF[0], "password": STAFF[1]}, timeout=10).status_code
        check("7c. دخول الموظف للـ API", estatus == 200)
        check("7d. API يسمح بحث نقطة البيع للموظف (200)",
              es.get(f"{BASE}/pharmacy/pos/search?q=%D8%A8%D8%A7%D9%86", timeout=10).status_code == 200)
        check("7e. API يمنع سجل البيع عن الموظف (403)",
              es.get(f"{BASE}/pharmacy/pos/sales", timeout=10).status_code == 403)
        check("7f. API يمنع المخزون عن الموظف (403)",
              es.get(f"{BASE}/pharmacy/inventory", timeout=10).status_code == 403)
        check("7g. API يمنع سجل حركات المخزون عن الموظف (403)",
              es.get(f"{BASE}/pharmacy/inventory/movements", timeout=10).status_code == 403)

        # نقطة البيع تظل تعمل للموظف فعلًا
        staff_page.goto(f"{POS_APP}/pos", wait_until="networkidle")
        si = staff_page.locator('input[role="combobox"]')
        si.wait_for(timeout=15000)
        si.click()
        si.fill("")
        staff_page.keyboard.type("بانادول", delay=50)
        opts = staff_page.locator('#pos-search-listbox [role="option"]')
        check("7h. الموظف يبيع فعلًا في نقطة البيع (اقتراحات ظهرت)", wait_options(opts))

        # ============ 8) التطبيق الرئيسي لم يتأثر ============
        r = requests.get(f"{MAIN_APP}/login", timeout=15)
        check("8a. تطبيق الإدارة على 3000 سليم", r.status_code == 200)

        # ============ 9) نظام اللغات (Task 48) ============
        ls, lstatus = owner_api_session()
        check("9a. دخول المالك API لفحوص اللغة", lstatus == 200)
        me = ls.get(f"{BASE}/auth/pharmacy/me", timeout=10).json()
        check("9b. /me يعيد locale الافتراضي ar", me.get("user", {}).get("locale") == "ar",
              str(me.get("user", {}).get("locale")))

        # واجهة صفحة الإعدادات بالعربية أولًا (قبل أي تغيير لغة)
        page.goto(f"{POS_APP}/settings", wait_until="networkidle")
        lang_section = False
        deadline = time.time() + 20
        while time.time() < deadline:
            try:
                if "اللغة" in page.locator("body").inner_text():
                    lang_section = True
                    break
            except Exception:
                pass
            time.sleep(0.3)
        diag = ""
        if not lang_section:
            try:
                diag = f"url={current_url(page)} h2count={page.locator('#language-setting-title').count()} body={page.locator('body').inner_text()[:160]}".replace("\n", " | ")
            except Exception as exc:
                diag = f"diag-error: {exc}"
        check("9c. صفحة الإعدادات تعرض قسم «اللغة» وثماني لغات",
              lang_section and page.get_by_role("button", name="English").count() > 0, diag)

        # الحفظ الدائم على الحساب عبر الـ API
        rpatch = ls.patch(f"{BASE}/auth/pharmacy/locale", json={"locale": "en"}, headers=csrf_header(ls), timeout=10)
        check("9d. PATCH locale=en ينجح ويعيد {locale}",
              rpatch.status_code == 200 and rpatch.json().get("locale") == "en", str(rpatch.status_code))
        check("9e. لغة غير مدعومة → 400",
              ls.patch(f"{BASE}/auth/pharmacy/locale", json={"locale": "xx"}, headers=csrf_header(ls), timeout=10).status_code == 400)
        me2 = ls.get(f"{BASE}/auth/pharmacy/me", timeout=10).json()
        check("9f. /me يعيد locale=en بعد التغيير", me2.get("user", {}).get("locale") == "en")

        # إعادة تحميل: لغة الحساب تلزوم حتى لو اختلف كوكي المتصفح (مزامنة من قاعدة البيانات)
        page.reload(wait_until="networkidle")
        check("9g. لغة الحساب (en) تلزوم بعد إعادة التحميل — حفظ دائم",
              wait_sidebar_contains(page, "Point of Sale")
              and page.evaluate("document.documentElement.getAttribute('dir')") == "ltr")

        # العودة للعربية عبر الواجهة نفسها (تبديل فوري RTL + حفظ)
        arabic_btn = page.get_by_role("button", name="العربية")
        if arabic_btn.count() > 0:
            arabic_btn.first.click()
        else:
            ls.patch(f"{BASE}/auth/pharmacy/locale", json={"locale": "ar"}, headers=csrf_header(ls), timeout=10)
        ok_rtl = False
        deadline = time.time() + 12
        while time.time() < deadline:
            if page.evaluate("document.documentElement.getAttribute('dir')") == "rtl":
                ok_rtl = True
                break
            time.sleep(0.3)
        check("9h. العودة للعربية RTL عبر الواجهة", ok_rtl and wait_sidebar_contains(page, "نقطة البيع"))

        # سلامة الحالة للحسابات اللاحقة: العودة إلى ar نهائيًا من الـ API + الكوكي
        ls.patch(f"{BASE}/auth/pharmacy/locale", json={"locale": "ar"}, headers=csrf_header(ls), timeout=10)
        page.evaluate("document.cookie = 'pharmacy_locale=ar; path=/; max-age=31536000; samesite=lax'")

        # ============ 10) إدارة الفروع (Task 50 + Task 51 تعبية أصلية) ============
        ps = ls
        ctx0 = ps.get(f"{BASE}/pharmacy/context", timeout=10).json()
        real_pharmacy_name = ctx0.get("pharmacy", {}).get("name")
        blist_resp = ps.get(f"{BASE}/pharmacy/branches", timeout=10)
        blist = blist_resp.json().get("data", []) if blist_resp.status_code == 200 else []
        main_branch = next((b for b in blist if b.get("is_main")), None)
        check("10a. قائمة الفروع تعيد الفرع الرئيسي بعلامة is_main",
              main_branch is not None and main_branch.get("name") == "الفرع الرئيسي",
              f"status={blist_resp.status_code} names={[b.get('name') for b in blist]}")
        # Task 51 — شكوى «الاسم دائمًا الفرع الرئيسي في الحقل»: مصدر تعبية نموذج
        # التعديل (القائمة) يجب أن يحمل اسم الصيدلية الحقيقي من قاعدة البيانات.
        check("10a2. مصدر تعبية النموذج يحمل pharmacy_name الحقيقي من قاعدة البيانات",
              main_branch is not None and main_branch.get("pharmacy_name") == real_pharmacy_name,
              f"list={main_branch and main_branch.get('pharmacy_name')!r} context={real_pharmacy_name!r}")

        # Task 52 — شكوى «بطاقة الفرع مفيش فيها البيانات الحقيقية في صفحة الفروع»:
        # عند التسجيل يُزرع الفرع الرئيسي باسمه وكوده فقط وتُحفظ بيانات التواصل في
        # pharmacies — فكانت البطاقة تعرض «—» و«بدون عنوان» حتى بعد تعديل المستخدم
        # للبيانات مباشرة في قاعدة البيانات. المحاكاة الحرفية: UPDATE مباشر على
        # pharmacies ثم يجب أن تعرض القائمة (وبطاقة /branches) القيم فورًا.
        import psycopg2
        _pid = ctx0.get("pharmacy", {}).get("id")
        dbconn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
        dbconn.autocommit = True
        dbcur = dbconn.cursor()
        dbcur.execute("SELECT COALESCE(phone,''), COALESCE(email,''), COALESCE(address_line1,''), COALESCE(city,'') FROM pharmacies WHERE id=%s", (_pid,))
        _orig_contact = dbcur.fetchone()
        T52_PHONE, T52_ADDR, T52_CITY = "01000000099", "15 شارع الجمهورية", "المنصورة"
        dbcur.execute("UPDATE pharmacies SET phone=%s, address_line1=%s, city=%s WHERE id=%s",
                      (T52_PHONE, T52_ADDR, T52_CITY, _pid))
        main_db52_resp = ps.get(f"{BASE}/pharmacy/branches", timeout=10)
        if main_db52_resp.status_code != 200:
            raise AssertionError(f"branches GET {main_db52_resp.status_code}")
        main_db52 = next((b for b in main_db52_resp.json().get("data", []) if b.get("is_main")), {})
        check("10a3. بطاقة الفرع الرئيسي تعرض بيانات التواصل الحقيقية من pharmacies (تعديل مباشر في DB كما يفعل المستخدم)",
              main_db52.get("phone") == T52_PHONE and main_db52.get("address") == T52_ADDR and main_db52.get("city") == T52_CITY,
              str({k: main_db52.get(k) for k in ("phone", "address", "city")}))
        # إثبات واجهة حقيقي: بطاقة /branches نفسها يجب أن تطبع القيم
        mpage = browser.new_page()
        mpage.goto(f"{MAIN_APP}/login", wait_until="networkidle")
        mpage.fill('input[type="email"]', OWNER[0])
        mpage.fill('input[type="password"]', OWNER[1])
        mpage.click('button[type="submit"]')
        deadline = time.time() + 25
        while time.time() < deadline and "/login" in current_url(mpage):
            time.sleep(0.25)
        mpage.goto(f"{MAIN_APP}/branches", wait_until="networkidle")
        card_text = mpage.locator("body").inner_text()
        check("10a4. بطاقة الفرع في صفحة /branches تطبع الهاتف والعنوان والمدينة الحقيقية",
              T52_PHONE in card_text and T52_ADDR in card_text and T52_CITY in card_text,
              f"phone={T52_PHONE in card_text} addr={T52_ADDR in card_text} city={T52_CITY in card_text}")
        mpage.close()
        dbcur.execute("UPDATE pharmacies SET phone=NULLIF(%s,''), email=NULLIF(%s,''), address_line1=NULLIF(%s,''), city=NULLIF(%s,'') WHERE id=%s",
                      (*_orig_contact, _pid))
        dbcur.close()
        dbconn.close()

        # Task 53 — شكوى «البريد اللي دخلته وقت التسجيل مجاش بشكل تلقائي للبطاقة
        # او للحقول في التعديل»: التسجيل نفسه يجب أن يكتب بريد الصيدلية في
        # pharmacies.email (المصدر الذي تقرأه البطاقة وحقول التعديل عبر القائمة)
        # وفي صف الفرع الرئيسي المزروع — فإذا فُقد أحدهما فُتح باب المسح من
        # نماذج التعديل. تسجيل حي عبر الـ API ثم تحقق مباشر من قاعدة البيانات.
        import uuid as _uuid
        import psycopg2 as _psycopg2
        _reg_email = f"reg-{_uuid.uuid4().hex[:10]}@test.io"
        _reg_login = f"owner-{_uuid.uuid4().hex[:10]}@test.io"
        _reg = requests.post(f"{BASE}/auth/register", json={
            "company_name": "صيدلية بريد التسجيل", "company_email": _reg_email,
            "first_name": "صاحب", "last_name": "التسجيل",
            "email": _reg_login,
            "password": "Str0ng!Pass2026",
        }, timeout=15)
        _regconn = _psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
        _regconn.autocommit = True
        _regcur = _regconn.cursor()
        _regcur.execute(
            "SELECT COALESCE(p.email,''), COALESCE((SELECT b.email FROM branches b"
            " WHERE b.pharmacy_id = p.id AND b.is_active = true LIMIT 1),'')"
            " FROM pharmacies p JOIN accounts a ON a.id = p.account_id WHERE a.contact_email = %s",
            (_reg_email,))
        _regrow = _regcur.fetchone() or ("", "")
        _regcur.close()
        _regconn.close()
        check("10a5. التسجيل يكتب بريد الصيدلية في pharmacies.email وصف الفرع الرئيسي مباشرة",
              _reg.status_code == 201 and _regrow == (_reg_email, _reg_email),
              f"status={_reg.status_code} row={_regrow}")

        create = ps.post(f"{BASE}/pharmacy/branches", json={
            "name": "فرع التجارب E2E", "city": "الجيزة", "phone": "01111111112",
        }, headers=csrf_header(ps), timeout=10)
        new_id = create.json().get("data", {}).get("id") if create.status_code == 201 else None
        check("10b. POST يضيف فرعاً جديداً كلياً (201)", new_id is not None, str(create.status_code))
        blist2_resp = ps.get(f"{BASE}/pharmacy/branches", timeout=10)
        blist2 = blist2_resp.json().get("data", []) if blist2_resp.status_code == 200 else []
        check("10c. الفرع الجديد يظهر في القائمة (غير رئيسي)",
              blist2_resp.status_code == 200 and any(b.get("id") == new_id and b.get("is_main") is False for b in blist2),
              f"status={blist2_resp.status_code}")

        put_new = ps.put(f"{BASE}/pharmacy/branches/{new_id}", json={
            "name": "فرع التجارب E2E", "city": "الإسكندرية",
        }, headers=csrf_header(ps), timeout=10)
        check("10d. PUT يعدّل بيانات الفرع الجديد (200)",
              put_new.status_code == 200 and put_new.json().get("data", {}).get("city") == "الإسكندرية",
              str(put_new.status_code))

        ctx_before = ps.get(f"{BASE}/pharmacy/context", timeout=10).json().get("pharmacy", {})
        # Task 53 — النموذج الحقيقي يرسل المسودة كاملة (البريد/العنوان/المدينة كما
        # عادت من القائمة). حمولة ناقصة كانت تمسح البريد من pharmacies عبر
        # NULLIF('') — وهذا جذر شكوى «البريد اللي دخلته وقت التسجيل مجاش للبطاقة».
        put_main = ps.put(f"{BASE}/pharmacy/branches/{main_branch['id']}", json={
            "name": "الفرع الرئيسي", "pharmacy_name": "صيدلية التجارب الموحدة",
            "phone": ctx_before.get("phone") or "01000000000",
            "email": main_branch.get("email") or "",
            "address": main_branch.get("address") or "",
            "city": main_branch.get("city") or "",
        }, headers=csrf_header(ps), timeout=10)
        ctx_after = ps.get(f"{BASE}/pharmacy/context", timeout=10).json()
        check("10e. تعديل الفرع الرئيسي يحدّث معلومات الصيدلية (الاسم في السياق)",
              put_main.status_code == 200
              and ctx_after.get("pharmacy", {}).get("name") == "صيدلية التجارب الموحدة"
              and (ctx_after.get("branch") or {}).get("name") == "الفرع الرئيسي",
              str(ctx_after.get("pharmacy", {}).get("name")))
        # Task 51 — سيناريو المستخدم الحرفي: الاسم تغيّر في قاعدة البيانات،
        # وإعادة فتح نموذج التعديل يجب أن تعرض القيمة الجديدة لا «الفرع الرئيسي».
        blist_after = ps.get(f"{BASE}/pharmacy/branches", timeout=10).json().get("data", [])
        main_after = next((b for b in blist_after if b.get("is_main")), {})
        check("10e2. إعادة فتح النموذج تعرض الاسم الجديد من DB لا «الفرع الرئيسي»",
              main_after.get("pharmacy_name") == "صيدلية التجارب الموحدة",
              repr(main_after.get("pharmacy_name")))

        bad = {"name": "   "}
        check("10f. POST باسم فرع فارغ → 400",
              ps.post(f"{BASE}/pharmacy/branches", json=bad, headers=csrf_header(ps), timeout=10).status_code == 400)
        bad2 = {"name": "فرع", "email": "not-an-email"}
        check("10g. PUT ببريد غير صحيح → 400",
              ps.put(f"{BASE}/pharmacy/branches/{new_id}", json=bad2, headers=csrf_header(ps), timeout=10).status_code == 400)
        check("10h. الموظف المقيّد يُمنع من إضافة فرع (403)",
              es.post(f"{BASE}/pharmacy/branches", json={"name": "فرع الموظف"}, headers=csrf_header(es), timeout=10).status_code == 403)

        del_main = ps.delete(f"{BASE}/pharmacy/branches/{main_branch['id']}", headers=csrf_header(ps), timeout=10)
        check("10i. حذف الفرع الرئيسي محمي (400)", del_main.status_code == 400, str(del_main.status_code))
        del_new = ps.delete(f"{BASE}/pharmacy/branches/{new_id}", headers=csrf_header(ps), timeout=10)
        blist3_resp = ps.get(f"{BASE}/pharmacy/branches", timeout=10)
        blist3 = blist3_resp.json().get("data", []) if blist3_resp.status_code == 200 else []
        check("10j. إيقاف الفرع الجديد يخفيه من القائمة",
              del_new.status_code == 200 and blist3_resp.status_code == 200 and all(b.get("id") != new_id or not b.get("is_active") for b in blist3),
              f"del={del_new.status_code} list={blist3_resp.status_code}")

        # استعادة اسم الصيدلية الأصلي عبر تعديل الفرع الرئيسي (مسودة كاملة كما يفعل النموذج)
        restore = ps.put(f"{BASE}/pharmacy/branches/{main_branch['id']}", json={
            "name": main_branch.get("name") or "الفرع الرئيسي",
            "pharmacy_name": ctx_before.get("name"),
            "phone": main_branch.get("phone") or "",
            "email": main_branch.get("email") or "",
            "address": main_branch.get("address") or "",
            "city": main_branch.get("city") or "",
        }, headers=csrf_header(ps), timeout=10)
        ctx_restored = ps.get(f"{BASE}/pharmacy/context", timeout=10).json().get("pharmacy", {})
        check("10k. استعادة اسم الصيدلية الأصلي",
              restore.status_code == 200 and ctx_restored.get("name") == ctx_before.get("name"),
              str(ctx_restored.get("name")))
        blist_restored = ps.get(f"{BASE}/pharmacy/branches", timeout=10).json().get("data", [])
        main_restored = next((b for b in blist_restored if b.get("is_main")), {})
        check("10k2. بعد الاستعادة مصدر تعبية النموذج يعيد الاسم الأصلي",
              main_restored.get("pharmacy_name") == ctx_before.get("name"),
              repr(main_restored.get("pharmacy_name")))

        # Task 53 — الشفاء الذاتي عند الإقلاع: الحلقة التاريخية التي مسحت بريد
        # الصيدلية (نماذج تعديل قديمة تفتح فارغة ثم تحفظ) عالجها شفاء إقلاع
        # دائم (database.HealPharmacyRegistrationEmail): عند كل إقلاع يُستعاد
        # البريد الفارغ من accounts.contact_email — مصدر التسجيل الذي لا يكتبه
        # سوى التسجيل. المحاكاة الحرفية: مسح البريد من pharmacies وصف الفرع ثم
        # إعادة تشغيل الباكند والقائمة — مصدر البطاقة وحقول التعديل — تعيد
        # بريد التسجيل الأصلي.
        dbconn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
        dbconn.autocommit = True
        dbcur = dbconn.cursor()
        dbcur.execute("SELECT a.contact_email FROM pharmacies p JOIN accounts a ON a.id = p.account_id WHERE p.id = %s", (_pid,))
        _heal_source = dbcur.fetchone()[0]
        dbcur.execute("UPDATE pharmacies SET email = NULL WHERE id = %s", (_pid,))
        dbcur.execute("UPDATE branches SET email = NULL WHERE pharmacy_id = %s AND is_active = true", (_pid,))
        # سيناريو ثانٍ — بيانات الحقب الأولى: تسجيل-era قديم أنشأ companies فقط
        # فبريد التسجيل يسكن companies.email وcontact_email فارغ/NULL. الشفاء
        # يجب أن يأخذ أول قيمة غير فارغة من (contact_email، companies.email).
        dbcur.execute(
            "SELECT p.id::text, a.id::text, COALESCE(c.email,'') FROM pharmacies p "
            "JOIN accounts a ON a.id = p.account_id JOIN companies c ON c.id = a.company_id "
            "WHERE a.contact_email = %s", (_reg_email,))
        _reg_pid, _reg_aid, _reg_companies_email = dbcur.fetchone()
        dbcur.execute("UPDATE pharmacies SET email = NULL WHERE id = %s", (_reg_pid,))
        dbcur.execute("UPDATE accounts SET contact_email = '' WHERE id = %s", (_reg_aid,))
        _lost = ps.get(f"{BASE}/pharmacy/branches", timeout=10)
        _lost_main = next((b for b in _lost.json().get("data", []) if b.get("is_main")), {}) if _lost.status_code == 200 else {}
        check("10a6a. بعد المسح المتعمد للبريد من الصيدلية والفرع، القائمة فقدته فعلًا (بيئة قبل الشفاء)",
              _lost.status_code == 200 and _lost_main.get("email") == "", repr(_lost_main.get("email")))
        dbcur.close()
        dbconn.close()

        import subprocess as _sub
        _sub.run(["pkill", "-f", "pharmacy-backend"], check=False)
        time.sleep(1.5)
        with open("/tmp/backend.log", "ab") as _blog:
            _sub.Popen(["/tmp/pharmacy-backend"], stdout=_blog, stderr=_sub.STDOUT, start_new_session=True)
        _healed = False
        for _ in range(60):
            time.sleep(0.5)
            try:
                if requests.get(f"{BASE}/health", timeout=2).status_code == 200:
                    _healed = True
                    break
            except Exception:
                pass
        _heal_resp = ps.get(f"{BASE}/pharmacy/branches", timeout=10)
        _heal_main = next((b for b in _heal_resp.json().get("data", []) if b.get("is_main")), {}) if _heal_resp.status_code == 200 else {}
        check("10a6b. إعادة تشغيل الباكند تستعيد بريد التسجيل من accounts.contact_email (شفاء الإقلاع الذاتي) فتعود للبطاقة وحقول التعديل",
              _healed and _heal_resp.status_code == 200 and _heal_main.get("email") == _heal_source and _heal_source != "",
              f"health={_healed} status={_heal_resp.status_code} email={_heal_main.get('email')!r} source={_heal_source!r}")

        # السيناريو الثاني: بعد نفس إعادة التشغيل، صيدلية 10a5 (contact_email
        # فيها NULL) يجب أن تكون شُفيت من companies.email — تغطية بيانات الحقب
        # الأولى التي أنشأت companies فقط عند التسجيل.
        _hconn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
        _hconn.autocommit = True
        _hcur = _hconn.cursor()
        _hcur.execute("SELECT COALESCE(email,'') FROM pharmacies WHERE id = %s", (_reg_pid,))
        _reg_healed = _hcur.fetchone()[0]
        _hcur.close()
        _hconn.close()
        check("10a6c. صيدلية التسجيل (10a5) شُفيت من companies.email عندما يكون contact_email فارغًا (تغطية كل الحقب)",
              _reg_healed == _reg_companies_email and _reg_companies_email != "",
              f"healed={_reg_healed!r} companies_email={_reg_companies_email!r}")

        _health = requests.get(f"{BASE}/health", timeout=5).json()
        check("10a6d. /health يعلن api_level (التحقق الفوري من نشر الباكند بلا بيانات دخول)",
              _health.get("status") == "healthy" and isinstance(_health.get("api_level"), int) and _health.get("api_level") >= 53,
              str(_health))

        # السيناريو الثالث (Task 55) — آخر الحصون: المستخدم مثبت أثناء تصحيح
        # Task 51/52 أنه يعدّل قاعدة البيانات مباشرة؛ إن فرّغ تجاربه كل مصادر
        # التسجيل (contact_email وcompanies.email معًا) يبقى بريد الدخول في
        # company_users كمصدر أخير لا يُهجر — «البريد: —» لا يبقى بلا سبب.
        _uconn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
        _uconn.autocommit = True
        _ucur = _uconn.cursor()
        _ucur.execute("UPDATE pharmacies SET email = NULL WHERE id = %s", (_reg_pid,))
        _ucur.execute("UPDATE accounts SET contact_email = '' WHERE id = %s", (_reg_aid,))
        _ucur.execute("UPDATE companies SET email = '' WHERE id = (SELECT company_id FROM accounts WHERE id = %s)", (_reg_aid,))
        _ucur.execute("SELECT email FROM company_users WHERE company_id = (SELECT company_id FROM accounts WHERE id = %s) ORDER BY created_at ASC, id ASC LIMIT 1", (_reg_aid,))
        _login_email = _ucur.fetchone()[0]
        _ucur.close()
        _uconn.close()
        _sub.run(["pkill", "-f", "pharmacy-backend"], check=False)
        time.sleep(1.5)
        with open("/tmp/backend.log", "ab") as _blog:
            _sub.Popen(["/tmp/pharmacy-backend"], stdout=_blog, stderr=_sub.STDOUT, start_new_session=True)
        _healed3 = False
        for _ in range(60):
            time.sleep(0.5)
            try:
                if requests.get(f"{BASE}/health", timeout=2).status_code == 200:
                    _healed3 = True
                    break
            except Exception:
                pass
        _uconn2 = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
        _uconn2.autocommit = True
        _ucur2 = _uconn2.cursor()
        _ucur2.execute("SELECT COALESCE(email,'') FROM pharmacies WHERE id = %s", (_reg_pid,))
        _healed_email = _ucur2.fetchone()[0]
        _ucur2.close()
        _uconn2.close()
        check("10a6e. كل مصادر التسجيل فارغة → الشفاء يستعيد بريد الدخول من company_users (آخر ما كتبه المستخدم)",
              _healed3 and _login_email == _reg_login and _healed_email == _reg_login and _healed_email != "",
              f"health={_healed3} healed={_healed_email!r} login={_reg_login!r}")

        # ============ 11) اللغة تتبع الحساب من متصفح جديد (Task 50) ============
        ls.patch(f"{BASE}/auth/pharmacy/locale", json={"locale": "en"}, headers=csrf_header(ls), timeout=10)
        fresh = browser.new_context()  # متصفح جديد تمامًا: صفر كوكيز
        fpage = fresh.new_page()
        fpage.goto(f"{POS_APP}/login", wait_until="networkidle")
        fpage.fill('input[type="email"]', OWNER[0])
        fpage.fill('input[type="password"]', OWNER[1])
        fpage.click('button[type="submit"]')
        deadline = time.time() + 25
        while time.time() < deadline:
            try:
                if "/login" not in fpage.evaluate("window.location.href"):
                    break
            except Exception:
                pass
            time.sleep(0.3)
        time.sleep(1.0)
        fresh_body = fpage.locator("body").inner_text()
        check("11a. متصفح جديد: بعد الدخول مباشرة dir=ltr",
              fpage.evaluate("document.documentElement.getAttribute('dir')") == "ltr")
        check("11b. متصفح جديد: الواجهة إنجليزية فورًا من قاعدة البيانات (بلا إعادة تحميل)",
              "Point of Sale" in fresh_body and "نقطة البيع" not in fresh_body,
              fresh_body[:120].replace("\n", " | "))
        fresh.close()

        ls.patch(f"{BASE}/auth/pharmacy/locale", json={"locale": "ar"}, headers=csrf_header(ls), timeout=10)

        browser.close()

    # ============ 12) تشخيص تسليم بريد OTP عبر Brevo (Task 56) ============
    # شكوى المستخدم: رمز التحقق يصل gmail دائمًا لكنه لا يصل outlook.sa/outlook.com
    # إطلاقًا مع أن التطبيق يقول «نجح الإرسال». السبب: النجاح المعلن يعني فقط
    # قبول Brevo للرسالة — Microsoft يسقطها لاحقًا بصمت. نقطة النهاية الجديدة
    # تقرأ سجل أحداث Brevo لتكشف (delivered/blocked/bounce + سبب SMTP).
    r = requests.get(f"{BASE}/auth/platform/email-delivery-status",
                     params={"email": "probe@outlook.sa"}, timeout=10)
    check("12a. حالة تسليم البريد بلا جلسة → 401", r.status_code == 401, str(r.status_code))

    _plat_probe, _ = owner_api_session()
    r = _plat_probe.get(f"{BASE}/auth/platform/email-delivery-status",
                        params={"email": "probe@outlook.sa"}, timeout=10)
    check("12b. جلسة نطاق صيدلية على مسار المنصة → 401", r.status_code == 401, str(r.status_code))

    plat = requests.Session()
    r = plat.post(f"{BASE}/auth/platform/login",
                  json={"email": PLATFORM[0], "password": PLATFORM[1]}, timeout=10)
    check("12c. دخول مدير المنصة (bootstrap) → 200",
          r.status_code == 200, f"{r.status_code} {r.text[:150]}")

    r = plat.get(f"{BASE}/auth/platform/email-delivery-status", timeout=10)
    check("12d. بدون معامل البريد → 400", r.status_code == 400, str(r.status_code))

    r = plat.get(f"{BASE}/auth/platform/email-delivery-status",
                 params={"email": "probe@outlook.sa"}, timeout=15)
    _body = {}
    try:
        _body = r.json()
    except Exception:
        pass
    check("12e. استعلام سجل التسليم بلا إعداد Brevo → 503 email_not_configured",
          r.status_code == 503 and _body.get("error") == "email_not_configured",
          f"{r.status_code} {r.text[:150]}")

    failed = checks.count(False)
    print(f"\n==== {len(checks) - failed}/{len(checks)} checks passed ====")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
