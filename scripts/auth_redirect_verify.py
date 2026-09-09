#!/usr/bin/env python3
"""Auth-aware redirect verification (Task 30).

Scenarios:
  Guest:  /login shows form | /start -> /register | marketing CTA -> /register
  Authed: /login -> / | /register -> / | /start -> / | marketing CTA -> dashboard

Requires: PG :54329 (reports_test), backend :8080, app :3000, marketing :3001
"""
import sys
import time

from playwright.sync_api import sync_playwright

APP = "http://localhost:3000"
MKT = "http://localhost:3001"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"

FAILURES = []


def check(name, cond, detail=""):
    print(f"  [{'PASS' if cond else 'FAIL'}] {name} {detail}")
    if not cond:
        FAILURES.append(name)


def goto_wait(page, url, timeout=30000):
    page.goto(url, wait_until="domcontentloaded", timeout=timeout)


def current_url(page):
    """Ground truth — page.url() can lag behind client-side router.replace()."""
    try:
        return page.evaluate("window.location.href")
    except Exception:
        return page.url


def wait_final_url(page, pred, timeout=20000, what=""):
    """Wait until client-side redirect settles at a URL satisfying pred."""
    deadline = time.time() + timeout / 1000
    while time.time() < deadline:
        if pred(current_url(page)):
            return True
        time.sleep(0.2)
    print(f"    [debug] stuck at {current_url(page)} (page.url={page.url})")
    return False


def is_dashboard_url(url):
    return url.rstrip("/") == APP and "/login" not in url and "/register" not in url and "/start" not in url


def has_dashboard_console_error(page):
    return False  # placeholder — console handled via page.on in main


def is_register_url(url):
    return url.startswith(f"{APP}/register")


def dash_ready(page):
    try:
        page.wait_for_selector("aside", timeout=8000)
        return True
    except Exception:
        return False


def attach_console(page, bucket):
    page.on("console", lambda m: bucket.append(f"[{m.type}] {m.text[:160]}"))
    page.on("pageerror", lambda e: bucket.append(f"[PAGEERROR] {str(e)[:250]}"))


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch()

        # ============ A) GUEST (no cookies) ============
        print("== A) زائر غير مسجل ==")
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        g = ctx.new_page()
        g_logs = []
        attach_console(g, g_logs)

        g.goto(f"{APP}/login", wait_until="networkidle")
        email_visible = g.locator('input[type="email"]').first.is_visible()
        check("guest:/login يعرض النموذج (لا تحويل)", email_visible, g.url)

        g.goto(f"{APP}/start", wait_until="domcontentloaded")
        ok = wait_final_url(g, is_register_url)
        reg_form = False
        if ok:
            try:
                g.wait_for_selector('input[placeholder="صيدلية الشفاء"]', timeout=8000)
                reg_form = True
            except Exception:
                pass
        check("guest:/start يحوّل إلى /register مع النموذج", ok and reg_form, g.url)

        g.goto(MKT, wait_until="networkidle")
        cta = g.locator("a.button.button-primary").first
        check("marketing: زر ابدأ الآن موجود", cta.count() > 0 or cta.is_visible())
        cta.click()
        ok = wait_final_url(g, is_register_url, timeout=25000)
        reg_form = False
        if ok:
            try:
                g.wait_for_selector('input[placeholder="صيدلية الشفاء"]', timeout=8000)
                reg_form = True
            except Exception:
                pass
        check("guest: ابدأ الآن → تطبيق /register", ok and reg_form, g.url)
        ctx.close()

        # ============ B) AUTHENTICATED ============
        print("== B) مستخدم مسجل الدخول ==")
        ctx2 = browser.new_context(viewport={"width": 1280, "height": 900})
        a = ctx2.new_page()
        a_logs = []
        attach_console(a, a_logs)

        # login via UI
        a.goto(f"{APP}/login", wait_until="networkidle")
        a.fill('input[type="email"]', EMAIL)
        a.fill('input[type="password"]', PASSWORD)
        a.click('button[type="submit"]')
        ok = wait_final_url(a, is_dashboard_url, timeout=30000)
        check("تسجيل الدخول يصل للوحة", ok and dash_ready(a), a.url)

        # reload /login while authed -> must bounce to /
        a.goto(f"{APP}/login", wait_until="domcontentloaded")
        ok = wait_final_url(a, is_dashboard_url, timeout=15000)
        form_gone = True
        if ok:
            time.sleep(0.6)
            try:
                form_gone = not a.locator('input[type="email"]').first.is_visible()
            except Exception:
                form_gone = True
        check("authed:/login (reload) → / بدون نموذج دخول", ok and form_gone, a.url)

        # /register while authed -> /
        a.goto(f"{APP}/register", wait_until="domcontentloaded")
        ok = wait_final_url(a, is_dashboard_url, timeout=15000)
        check("authed:/register → /", ok and dash_ready(a), a.url)

        # /start while authed -> /
        a.goto(f"{APP}/start", wait_until="domcontentloaded")
        ok = wait_final_url(a, is_dashboard_url, timeout=15000)
        check("authed:/start → /", ok and dash_ready(a), a.url)

        # marketing CTA while authed -> dashboard
        a.goto(MKT, wait_until="networkidle")
        a.locator("a.button.button-primary").first.click()
        ok = wait_final_url(a, is_dashboard_url, timeout=25000)
        check("authed: ابدأ الآن → لوحة التحكم", ok and dash_ready(a), a.url)
        if not ok:
            print("    [console-tail]", a_logs[-8:] if a_logs else "empty")
        ctx2.close()

        browser.close()

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {FAILURES}")
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
