#!/usr/bin/env python3
"""E2E: POS smart search dropdown + fuzzy + scanner tolerance (Task 32)."""
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

        # POS page
        page.goto(f"{APP}/pos", wait_until="networkidle")
        search_input = page.locator('input[role="combobox"]')
        search_input.wait_for(timeout=10000)
        check("حقل البحث الذكي موجود", search_input.is_visible())

        def open_dropdown(query, expect_min=1, timeout=6000):
            search_input.click()
            search_input.fill("")
            page.keyboard.type(query, delay=60)
            deadline = time.time() + timeout / 1000
            while time.time() < deadline:
                options = page.locator('#pos-search-listbox [role="option"]')
                if options.count() >= expect_min:
                    return options
                time.sleep(0.2)
            return page.locator('#pos-search-listbox [role="option"]')

        # 1) name prefix typing → dropdown with كاربيمازول
        options = open_dropdown("كاربيما")
        texts = [options.nth(i).inner_text() for i in range(options.count())]
        check("dropdown بالاسم (كاربيما)", options.count() >= 2 and any("كاربيمازول" in t for t in texts), f"{options.count()} خيارات")

        # 1b) persistence: clicking outside does NOT close the list (linked to text)
        page.click("h1")  # ضغط في مكان فارغ خارج الحقل
        time.sleep(0.4)
        options = page.locator('#pos-search-listbox [role="option"]')
        check("الضغط خارج الحقل لا يغلق القائمة", options.count() >= 1, f"{options.count()} خيار بعد الضغط الخارج")

        # 1c) Escape closes deliberately → ArrowDown reopens from cache → clearing text closes
        search_input.click()
        page.keyboard.press("Escape")
        time.sleep(0.3)
        check("Escape يغلق القائمة عمداً", page.locator('#pos-search-listbox').count() == 0)
        page.keyboard.press("ArrowDown")
        time.sleep(0.3)
        check("السهم لأسفل يعيد فتح القائمة", page.locator('#pos-search-listbox [role="option"]').count() >= 1)
        search_input.fill("")
        time.sleep(0.3)
        check("مسح النص يغلق القائمة (مرتبطة بالنص)", page.locator('#pos-search-listbox').count() == 0)

        # 2) keyboard: ArrowDown + Enter adds to cart
        open_dropdown("كاربيما")
        page.keyboard.press("ArrowDown")
        page.keyboard.press("Enter")
        time.sleep(0.6)
        cart_lines = page.locator("text=علبة كاملة").count()
        check("Enter يضيف للفاتورة", cart_lines >= 1)

        # 3) heavy garble كانبيبالول → fuzzy tier-2 suggestion
        options = open_dropdown("كانبيبالول")
        texts = [options.nth(i).inner_text() for i in range(options.count())]
        check("dropdown ضبابي (كانبيبالول→كاربيمازول)", any("كاربيمازول" in t for t in texts), texts[:2])

        # pick it
        options.first.click()
        time.sleep(0.5)
        check("الاختيار بالنقر يضيف للفاتورة", page.locator("text=علبة كاملة").count() >= 2)

        # 4) scanner: exact barcode + Enter
        search_input.click()
        search_input.fill("")
        page.keyboard.type("6221004000012", delay=15)
        page.keyboard.press("Enter")
        time.sleep(1.2)
        check("باركود تام + Enter يضيف (بانادول)", page.locator("text=بانادول اكسترا").count() >= 1)

        # 5) scanner misread (2-digit change, low confidence): dropdown opens, Enter picks top
        search_input.click()
        search_input.fill("")
        page.keyboard.type("6221031500101", delay=15)  # misread of 6221031500011
        page.keyboard.press("Enter")
        time.sleep(1.5)
        body = page.locator("body").inner_text()
        check("الماسح المخطئ يفتح قائمة التأكيد", "الباركود غير مطابق تماماً" in body)
        options = page.locator('#pos-search-listbox [role="option"]')
        check("القائمة تعرض البديل الصحيح", options.count() >= 1 and "كاربيمازول" in options.first.inner_text())
        page.keyboard.press("Enter")  # cashier confirms top suggestion
        time.sleep(0.8)
        check("التأكيد بالـ Enter يضيف للفاتورة", page.locator("text=كاربيمازول 200mg").count() >= 1)

        # 5b) scanner misread (single char, high confidence) → AUTO-add + message
        search_input.click()
        search_input.fill("")
        page.keyboard.type("6221031500012", delay=15)  # 1-char misread of كاربيمازول barcode
        page.keyboard.press("Enter")
        time.sleep(1.5)
        body = page.locator("body").inner_text()
        check("خطأ الماسح الواقعي يُصحح تلقائياً", "تم التعرف على المنتج رغم خطأ الماسح" in body)

        # screenshot of final state with dropdown open
        options = open_dropdown("كونجست")
        page.screenshot(path="/tmp/pos_dropdown.png")
        check("لقطة القائمة المنسدلة محفوظة", True)

        browser.close()

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {FAILURES}")
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
