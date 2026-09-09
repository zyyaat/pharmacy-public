#!/usr/bin/env python3
"""E2E: receipt settings system (Task 34) — settings tab, live preview,
test print, persistence, POS auto/manual printing flows."""
import sys
import time

import psycopg2
from playwright.sync_api import sync_playwright

APP = "http://localhost:3000"
API = "http://localhost:8080"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"

FAILURES = []


def reset_settings():
    """إعادة ضبط إعدادات الصيدلية للافتراضي حتى يكون الاختبار محدداً في كل تشغيل"""
    try:
        conn = psycopg2.connect(host="127.0.0.1", port=54329, dbname="reports_test", user="postgres")
        conn.autocommit = True
        conn.cursor().execute("UPDATE pharmacies SET settings = '{}'::jsonb")
        conn.close()
        print("  [READY] إعدادات الفاتورة أُعيد ضبطها للافتراضي")
    except Exception as cause:
        print(f"  [WARN] تخطي إعادة الضبط: {cause}")


def check(name, cond, detail=""):
    print(f"  [{'PASS' if cond else 'FAIL'}] {name} {detail}")
    if not cond:
        FAILURES.append(name)


def current_url(page):
    try:
        return page.evaluate("window.location.href")
    except Exception:
        return page.url


def stub_window_print(page):
    """window.print in headless returns instantly and the printer unmounts
    its portal right after — capture the receipt HTML at print time."""
    page.evaluate("""() => {
        window.__prints = 0
        window.print = () => {
            window.__prints += 1
            window.__receiptHTML = document.getElementById('receipt-print-host')?.innerHTML || ''
        }
    }""")


def main():
    reset_settings()
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
        while time.time() < deadline:
            if current_url(page).rstrip("/") == APP:
                break
            time.sleep(0.2)
        check("تسجيل الدخول", "/login" not in current_url(page), current_url(page))

        # ---------- A) settings page: defaults + live preview ----------
        page.goto(f"{APP}/settings", wait_until="networkidle")
        page.wait_for_selector('text=مقاس الورقة', timeout=15000)
        check("صفحة الإعدادات بتبويب الفواتير", page.locator('[role="tab"][aria-selected="true"]', has_text="الفواتير والطباعة").count() == 1)
        page.wait_for_selector('div[style*="width: 80mm"]', timeout=8000)
        check("معاينة حية بعرض 80mm افتراضياً", page.locator('div[style*="width: 80mm"]').count() >= 1)
        check("80mm مختار افتراضياً", page.locator('button[aria-pressed="true"]', has_text="80 ملم").count() == 1)
        check("الوضع التلقائي افتراضياً", page.locator('button[aria-pressed="true"]', has_text="تلقائي").count() == 1)
        preview_text = page.locator('div[style*="width: 80mm"]').inner_text()
        check("المعاينة تحوي بيانات الصيدلية والأصناف", "بانادول اكسترا" in preview_text and "الإجمالي" in preview_text)
        check("المعاينة تعرض تركيز الدواء بجانب الاسم", "كونجستال أقراص 500mg" in preview_text and "بانادول اكسترا 500mg" in preview_text)
        check("حارس الجرعة: اسم يحمل جرعة أصلاً لا يُكرر تركيزه", "200mg 500mg" not in preview_text)

        # ---------- B) test print (uses draft, print stubbed) ----------
        stub_window_print(page)
        page.click('button:has-text("طباعة اختبار")')
        page.wait_for_timeout(700)
        prints = page.evaluate("window.__prints")
        receipt_html = page.evaluate("window.__receiptHTML || ''")
        check("الطباعة الاختبارية تفتح نافذة الطباعة", prints == 1, f"prints={prints}")
        check("الإيصال المطبوع يحمل رأس الصيدلية والأصناف", "بانادول اكسترا" in receipt_html and "INV-" in receipt_html)
        check("قاعدة @page بعرض الورق الصحيح", "@page" in receipt_html and "80mm" in receipt_html, "80mm rule")

        # ---------- C) change settings → save → reload → persisted ----------
        page.click('button:has-text("58 ملم")')
        page.wait_for_selector('div[style*="width: 58mm"]', timeout=5000)
        check("المعاينة تتقلص فوراً لعرض 58mm", page.locator('div[style*="width: 58mm"]').count() >= 1)
        page.click('button:has-text("يدوي")')
        page.locator('input[type="checkbox"]').first.check()
        thanks = page.locator('input[maxlength="120"]')
        thanks.fill("شكراً لزيارتكم — صيدليتكم الأهلية")
        page.click('button:has-text("حفظ الإعدادات")')
        page.wait_for_selector('text=تم حفظ الإعدادات وتطبيقها على كل الأجهزة', timeout=8000)
        check("حفظ الإعدادات ينجح مع رسالة تأكيد", True)
        page.reload(wait_until="networkidle")
        page.wait_for_selector('text=مقاس الورقة', timeout=15000)
        page.wait_for_timeout(600)
        check("58mm محفوظة بعد إعادة التحميل", page.locator('button[aria-pressed="true"]', has_text="58 ملم").count() == 1)
        check("الوضع اليدوي محفوظ", page.locator('button[aria-pressed="true"]', has_text="يدوي").count() == 1)
        check("النص المخصص محفوظ", page.locator('input[maxlength="120"]').input_value() == "شكراً لزيارتكم — صيدليتكم الأهلية")
        # نسختان مفعّلتان ⇒ الطباعة الاختبارية تعرض نسخة الصيدلية وخط القص
        stub_window_print(page)
        page.click('button:has-text("طباعة اختبار")')
        page.wait_for_timeout(700)
        receipt_html = page.evaluate("window.__receiptHTML || ''")
        check("نسختان مع خط قص في الطباعة", "نسخة الصيدلية" in receipt_html and "قص هنا" in receipt_html)
        check("قاعدة @page تحدثت لـ 58mm", "58mm" in receipt_html)

        # ---------- C2) بادئة اسم الصيدلية: chips + تركيب ذكي + نص مخصص + ثبات ----------
        # الاسم المسجل لصيدلية الاختبار: «صيدلية الشفاء»
        prefix_row = page.locator('p:has-text("يظهر على الفاتورة")')
        page.wait_for_timeout(300)
        check("بدون بادئة مختارة افتراضياً", page.get_by_role("button", name="بدون بادئة", exact=True).get_attribute("aria-pressed") == "true")
        check("بلا بادئة: الاسم كما هو مسجّل", "صيدلية الشفاء" in prefix_row.inner_text())
        # حارس التكرار: بادئة «صيدلية» على اسم يبدأ بـ«صيدلية» لا تكررها
        page.get_by_role("button", name="صيدلية", exact=True).click()
        page.wait_for_timeout(200)
        check("حارس التكرار: صيدلية + صيدلية الشفاء بلا تكرار", "صيدلية صيدلية" not in prefix_row.inner_text() and "صيدلية الشفاء" in prefix_row.inner_text())
        # بادئة تنتهي بنقطة تُلصق بالاسم بلا مسافة (نفس مثال المستخدم)
        page.get_by_role("button", name="صيدلية د.", exact=True).click()
        page.wait_for_timeout(200)
        check("صيدلية د. تُلصق بالاسم مباشرة", "صيدلية د.صيدلية الشفاء" in prefix_row.inner_text())
        # نص مخصص: غير البادئات الجاهزة يُركّب بمسافة
        page.locator('input[maxlength="40"]').fill("الفارما")
        page.wait_for_timeout(200)
        check("البادئة المخصصة تُركّب بمسافة", "الفارما صيدلية الشفاء" in prefix_row.inner_text())
        page.click('button:has-text("حفظ الإعدادات")')
        page.wait_for_selector('text=تم حفظ الإعدادات وتطبيقها على كل الأجهزة', timeout=8000)
        page.reload(wait_until="networkidle")
        page.wait_for_selector('text=اسم الصيدلية على الفاتورة', timeout=15000)
        page.wait_for_timeout(600)
        check("البادئة المخصصة محفوظة بعد إعادة التحميل", page.locator('input[maxlength="40"]').input_value() == "الفارما")
        check("المعاينة بعد التحميل بالتركيب المحفوظ", "الفارما صيدلية الشفاء" in page.locator('p:has-text("يظهر على الفاتورة")').inner_text())
        # نعتّد ببادئة «صيدلية د.» حتى تصل للطباعة الفعلية في قسمي POS التاليين
        page.get_by_role("button", name="صيدلية د.", exact=True).click()
        page.click('button:has-text("حفظ الإعدادات")')
        page.wait_for_selector('text=تم حفظ الإعدادات وتطبيقها على كل الأجهزة', timeout=8000)

        # ---------- D) POS manual mode: button after save ----------
        page.goto(f"{APP}/pos", wait_until="networkidle")
        search_input = page.locator('input[role="combobox"]')
        search_input.wait_for(timeout=10000)
        stub_window_print(page)
        search_input.click()
        search_input.fill("")
        page.keyboard.type("كاربيما", delay=50)
        options = page.locator('#pos-search-listbox [role="option"]')
        deadline = time.time() + 8
        while time.time() < deadline and options.count() == 0:
            time.sleep(0.2)
        check("اقتراحات البحث تعرض تركيز الدواء", "500mg" in page.locator('#pos-search-listbox').inner_text())
        options.first.click()
        body_text = page.locator('body').inner_text()
        check("سلة الفاتورة قبل البيع تعرض الاسم دون تكرار الجرعة", "كاربيمازول 200mg" in body_text and "200mg 500mg" not in body_text)
        page.click('button:has-text("إتمام البيع")')
        page.wait_for_selector('text=طباعة الفاتورة', timeout=10000)
        time.sleep(0.8)
        check("الوضع اليدوي يعرض زر طباعة بعد الحفظ", page.locator('button:has-text("طباعة الفاتورة")').count() == 1)
        check("الوضع اليدوي لا يطبع تلقائياً", page.evaluate("window.__prints") == 0)
        page.click('button:has-text("طباعة الفاتورة")')
        page.wait_for_timeout(900)
        receipt_html = page.evaluate("window.__receiptHTML || ''")
        check("الطباعة اليدوية تطبع إيصال الفاتورة الحقيقية", page.evaluate("window.__prints") == 1 and "فاتورة رقم" in receipt_html and "كاربيمازول" in receipt_html, f"html_len={len(receipt_html)}")

        # ---------- E) back to auto: sale prints by itself ----------
        page.goto(f"{APP}/settings", wait_until="networkidle")
        page.wait_for_selector('text=مقاس الورقة', timeout=15000)
        page.click('button:has-text("تلقائي")')
        page.click('button:has-text("حفظ الإعدادات")')
        page.wait_for_selector('text=تم حفظ الإعدادات وتطبيقها', timeout=8000)
        page.goto(f"{APP}/pos", wait_until="networkidle")
        search_input = page.locator('input[role="combobox"]')
        search_input.wait_for(timeout=10000)
        stub_window_print(page)
        search_input.click()
        search_input.fill("")
        page.keyboard.type("كونجست", delay=50)
        options = page.locator('#pos-search-listbox [role="option"]')
        deadline = time.time() + 8
        while time.time() < deadline and options.count() == 0:
            time.sleep(0.2)
        check("اقتراحات كونجست تعرض تركيز الدواء", "500mg" in page.locator('#pos-search-listbox').inner_text())
        options.first.click()
        page.click('button:has-text("إتمام البيع")')
        page.wait_for_timeout(1600)
        receipt_html = page.evaluate("window.__receiptHTML || ''")
        check("الوضع التلقائي يفتح الطباعة فوراً بعد الحفظ", page.evaluate("window.__prints") == 1)
        check("إيصال البيع التلقائي يحمل الفاتورة والإجمالي", "فاتورة رقم" in receipt_html and "INV-" in receipt_html)
        check("إيصال البيع يعرض تركيز الدواء", "500mg" in receipt_html and "كونجستال" in receipt_html)
        check("إيصال البيع يحمل الاسم المركب بالبادئة", "صيدلية د.صيدلية الشفاء" in receipt_html)

        # screenshot of settings preview for the record (paper stays at the
        # persisted 58mm from the persistence test — that's correct behavior)
        page.goto(f"{APP}/settings", wait_until="networkidle")
        page.wait_for_selector('text=مقاس الورقة', timeout=15000)
        page.wait_for_selector('div[style*="width: 58mm"]', timeout=10000)
        page.screenshot(path="/tmp/receipt_settings.png", full_page=True)
        check("لقطة صفحة الإعدادات محفوظة", True)

        browser.close()

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {FAILURES}")
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
