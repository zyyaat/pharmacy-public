#!/usr/bin/env python3
"""E2E: product edit as a full page (Task 37) — the edit button navigates to
/inventory/edit/[productId] (same form as creation, no modal at all), the
strength & dosage-form fields are editable, and changes show on the inventory
row right away (guard included)."""
import sys
import time

from playwright.sync_api import sync_playwright

APP = "http://localhost:3000"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"

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

        # ---------- A) inventory → edit opens a full page, not a modal ----------
        page.goto(f"{APP}/inventory", wait_until="networkidle")
        page.wait_for_selector('tbody tr', timeout=15000)
        row = page.locator('tbody tr', has_text='مرهم جروح').first
        row.locator('a', has_text='تعديل').click()
        deadline = time.time() + 20
        while time.time() < deadline and "/inventory/edit/" not in current_url(page):
            time.sleep(0.2)
        check("زر التعديل ينقل لصفحة كاملة", "/inventory/edit/" in current_url(page), current_url(page))
        page.wait_for_selector('text=بيانات العلاج', timeout=20000)
        check("عنوان صفحة التعديل ظاهر (لا نافذة)", page.locator('h1', has_text='تعديل المنتج').count() == 1)
        check("المودال أُلغي خالصاً: لا role=dialog في الصفحة", page.locator('[role="dialog"]').count() == 0)
        # the full creation form is here: dosage form select (custom combobox
        # with a hidden named input) + strength input
        check("نموذج الإضافة الكامل: الشكل الدوائي موجود", page.locator('input[type="hidden"][name="dosage_form"]').count() == 1)
        check("نموذج الإضافة الكامل: حقل التركيز موجود", page.locator('input[name="strength"]').count() == 1)
        # values prefilled from the stored product
        page.wait_for_timeout(500)
        check("البيانات محمّلة من المنتج: الاسم", page.locator('input[name="name"]').input_value() == "مرهم جروح")
        check("الأسعار محمّلة بالجنيه", page.locator('input[name="selling_price"]').input_value() not in ("", "0"))

        # ---------- B) edit the strength and save ----------
        page.locator('input[name="strength"]').fill("5%")
        page.click('button:has-text("حفظ التعديلات")')
        deadline = time.time() + 20
        while time.time() < deadline and current_url(page).rstrip("/").endswith("/inventory") is False:
            time.sleep(0.2)
        check("الحفظ يعيد لصفحة المخزون", current_url(page).rstrip("/").endswith("/inventory"), current_url(page))
        page.wait_for_selector('tbody tr', timeout=15000)
        saved_row = page.locator('tbody tr', has_text='مرهم جروح').first.inner_text()
        check("التركيز الجديد يظهر بجانب الاسم في المخزون", "مرهم جروح" in saved_row and "5%" in saved_row, saved_row[:60].replace("\n", " "))

        # ---------- C) restore: edit again and clear the strength ----------
        page.locator('tbody tr', has_text='مرهم جروح').first.locator('a', has_text='تعديل').click()
        page.wait_for_selector('input[name="strength"]', timeout=20000)
        page.wait_for_timeout(500)
        check("التعديل الثاني يحمل التركيز المحفوظ", page.locator('input[name="strength"]').input_value() == "5%")
        page.locator('input[name="strength"]').fill("")
        page.click('button:has-text("حفظ التعديلات")')
        deadline = time.time() + 20
        while time.time() < deadline and "/inventory/edit/" in current_url(page):
            time.sleep(0.2)
        page.wait_for_selector('tbody tr', timeout=15000)
        restored_row = page.locator('tbody tr', has_text='مرهم جروح').first.inner_text()
        check("الإلغاء يعيد الحالة: بلا تركيز بجانب الاسم", "مرهم جروح" in restored_row and "5%" not in restored_row, restored_row[:60].replace("\n", " "))

        browser.close()

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {FAILURES}")
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
