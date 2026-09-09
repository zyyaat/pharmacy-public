#!/usr/bin/env python3
"""E2E: product edit as a full page (Task 37) + strength number/unit dropdown
(Task 38). The edit button navigates to /inventory/edit/[productId] (same form
as creation, no modal), the strength field is a number input plus a unit
dropdown (mg / mcg / g / ml / mg/ml / IU / % / other) — the doctor types only
«50» and picks «mg». Existing stored strengths are split back into number +
unit on load, and unknown formats stay intact under «أخرى»."""
import sys
import time

from playwright.sync_api import sync_playwright

APP = "http://localhost:3000"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"

UNIT_COMBOBOX = 'div:has(> input[type="hidden"][name="strength_unit"]) > button[role="combobox"]'
UNIT_HIDDEN = 'input[type="hidden"][name="strength_unit"]'
LEGAL_UNITS = {"mg", "mcg", "g", "ml", "mg/ml", "IU", "%", "other"}

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


def wait_url(page, substring, want=True, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if (substring in current_url(page)) == want:
            return True
        time.sleep(0.2)
    return False


def wait_url_end(page, suffix, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if current_url(page).rstrip("/").endswith(suffix):
            return True
        time.sleep(0.2)
    return False


def pick_unit(page, label_substring):
    page.locator(UNIT_COMBOBOX).click()
    page.locator('div[role="option"]', has_text=label_substring).first.click()


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        page = ctx.new_page()

        # login
        page.goto(f"{APP}/login", wait_until="networkidle")
        page.fill('input[type="email"]', EMAIL)
        page.fill('input[type="password"]', PASSWORD)
        page.click('button[type="submit"]')
        wait_url(page, "/login", want=False)
        check("تسجيل الدخول", "/login" not in current_url(page), current_url(page))

        # ---------- A) inventory → edit opens a full page, not a modal ----------
        page.goto(f"{APP}/inventory", wait_until="networkidle")
        page.wait_for_selector('tbody tr', timeout=15000)
        row = page.locator('tbody tr', has_text='مرهم جروح').first
        row.locator('a', has_text='تعديل').click()
        check("زر التعديل ينقل لصفحة كاملة", wait_url(page, "/inventory/edit/"), current_url(page))
        page.wait_for_selector('text=بيانات العلاج', timeout=20000)
        check("عنوان صفحة التعديل ظاهر (لا نافذة)", page.locator('h1', has_text='تعديل المنتج').count() == 1)
        check("المودال أُلغي خالصاً: لا role=dialog في الصفحة", page.locator('[role="dialog"]').count() == 0)
        check("حقل رقم التركيز موجود", page.locator('input[name="strength_value"]').count() == 1)
        check("قائمة وحدات التركيز موجودة", page.locator(UNIT_HIDDEN).count() == 1)
        page.wait_for_timeout(500)
        check("الوحدة ضمن القائمة المعروفة", page.locator(UNIT_HIDDEN).input_value() in LEGAL_UNITS,
              page.locator(UNIT_HIDDEN).input_value())
        check("البيانات محمّلة من المنتج: الاسم", page.locator('input[name="name"]').input_value() == "مرهم جروح")
        check("الأسعار محمّلة بالجنيه", page.locator('input[name="selling_price"]').input_value() not in ("", "0"))

        # ---------- B) edit strength as number + unit (5 + % → 5%) ----------
        page.locator('input[name="strength_value"]').fill("5")
        pick_unit(page, "نسبة مئوية")
        check("الوحدة المختارة ظهرت على الزر", "نسبة مئوية" in page.locator(UNIT_COMBOBOX).inner_text())
        page.click('button:has-text("حفظ التعديلات")')
        check("الحفظ يعيد لصفحة المخزون", wait_url_end(page, "/inventory"), current_url(page))
        page.wait_for_selector('tbody tr', timeout=15000)
        saved_row = page.locator('tbody tr', has_text='مرهم جروح').first.inner_text()
        check("التركيب المخزّن: 5 + % تظهر 5% بجانب الاسم",
              "مرهم جروح" in saved_row and "5%" in saved_row, saved_row[:60].replace("\n", " "))

        # ---------- C) reload: stored «5%» splits back to 5 + % , then clear ----------
        page.locator('tbody tr', has_text='مرهم جروح').first.locator('a', has_text='تعديل').click()
        page.wait_for_selector('input[name="strength_value"]', timeout=20000)
        page.wait_for_timeout(500)
        check("التعديل الثاني: الرقم المفكّك من 5%", page.locator('input[name="strength_value"]').input_value() == "5",
              page.locator('input[name="strength_value"]').input_value())
        check("التعديل الثاني: الوحدة المحفوظة %", page.locator(UNIT_HIDDEN).input_value() == "%")
        page.locator('input[name="strength_value"]').fill("")
        page.click('button:has-text("حفظ التعديلات")')
        wait_url(page, "/inventory/edit/", want=False)
        page.wait_for_selector('tbody tr', timeout=15000)
        restored_row = page.locator('tbody tr', has_text='مرهم جروح').first.inner_text()
        check("الإلغاء يعيد الحالة: بلا تركيز بجانب الاسم",
              "مرهم جروح" in restored_row and "5%" not in restored_row, restored_row[:60].replace("\n", " "))

        # ---------- D) new product: number only «50» + default unit mg (طلب المستخدم) ----------
        barcode = f"{int(time.time() * 1000) % 10 ** 13:013d}"
        page.goto(f"{APP}/inventory/new", wait_until="networkidle")
        page.wait_for_selector('text=بيانات العلاج', timeout=20000)
        check("الوحدة الافتراضية للمنتج الجديد mg", page.locator(UNIT_HIDDEN).input_value() == "mg")
        page.fill('input[name="name"]', "تجربة تركيز 50")
        page.fill('input[name="barcode"]', barcode)
        page.locator('input[name="strength_value"]').fill("50")
        page.fill('input[name="initial_boxes"]', "1")
        page.fill('input[name="cost_price"]', "30")
        page.fill('input[name="selling_price"]', "45")
        page.click('button:has-text("حفظ المنتج")')
        check("حفظ المنتج الجديد يعيد للمخزون", wait_url_end(page, "/inventory"), current_url(page))
        page.wait_for_selector('tbody tr', timeout=15000)
        new_row = page.locator('tbody tr', has_text='تجربة تركيز 50').first.inner_text()
        check("الدكتور كتب 50 واختر mg → الصف تعرض 50mg",
              "تجربة تركيز 50" in new_row and "50mg" in new_row, new_row[:60].replace("\n", " "))

        browser.close()

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {FAILURES}")
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
