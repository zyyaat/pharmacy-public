#!/usr/bin/env python3
"""Print-overflow verification for the 3 report pages (Task 28 fix).

Logs in with a real session, emulates PRINT media, numerically checks that
every table inside .print-sheet (and its last column) fits the A4 printable
box, then exports real PDFs honoring @page CSS.

Usage: python3 scripts/print_verify.py
Requires: backend :8080 + frontend dev :3000 already running, seeded user
  print-test@test.io / Str0ng!Pass2026
"""
import os
import sys
import time

from playwright.sync_api import sync_playwright

BASE = "http://localhost:3000"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"
OUT = "/home/z/my-project/print-verify"
REPORTS = [
    ("movements", "/reports/movements"),
    ("sales", "/reports/sales"),
    ("inventory", "/reports/inventory"),
]
# A4 794px @96dpi; @page margin 10mm => 37.8px each side
PRINTABLE = 794 - 2 * 37.8  # ~718.4px

FAILURES = []


def check(name, cond, detail=""):
    print(f"  [{'PASS' if cond else 'FAIL'}] {name} {detail}")
    if not cond:
        FAILURES.append(name)


def main():
    os.makedirs(OUT, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1280, "height": 900})

        # ---- login ----
        print("== login ==")
        page.goto(f"{BASE}/login", wait_until="networkidle")
        page.fill('input[type="email"]', EMAIL)
        page.fill('input[type="password"]', PASSWORD)
        page.click('button[type="submit"]')
        page.wait_for_url(lambda url: "/login" not in url, timeout=30000)
        print("  logged in ->", page.url)

        for name, path in REPORTS:
            print(f"== {name} ==")
            page.goto(f"{BASE}{path}", wait_until="networkidle")
            # wait for at least one table row of real data
            page.wait_for_selector(".print-sheet table tbody tr", timeout=30000)
            time.sleep(1.0)  # let charts/KPIs settle

            # ---- print media emulation + numeric audit ----
            # emulate_media only switches CSS rules; the real print layout
            # viewport is the paper printable box (A4 794px - 2×10mm ≈ 718px).
            page.set_viewport_size({"width": int(PRINTABLE), "height": 1100})
            page.emulate_media(media="print")
            time.sleep(0.3)
            audit = page.evaluate("""() => {
                const limit = %f;
                const out = [];
                document.querySelectorAll('.print-sheet table').forEach((t, ti) => {
                    const r = t.getBoundingClientRect();
                    const headers = [...t.querySelectorAll('thead th')].map(th => {
                        const h = th.getBoundingClientRect();
                        return {text: th.textContent.trim(), left: +h.left.toFixed(1), right: +h.right.toFixed(1)};
                    });
                    out.push({
                        table: ti,
                        left: +r.left.toFixed(1),
                        right: +r.right.toFixed(1),
                        width: +r.width.toFixed(1),
                        fits: r.left >= -0.5 && r.right <= limit + 0.5,
                        headers,
                        lastHeader: headers.length ? headers[headers.length-1] : null,
                    });
                });
                return {
                    limit: +limit.toFixed(1),
                    pageScrollWidth: document.documentElement.scrollWidth,
                    tables: out,
                };
            }""" % PRINTABLE)

            print(f"  printable width: {audit['limit']}px, page scrollWidth: {audit['pageScrollWidth']}px")
            check("page has no horizontal overflow", audit["pageScrollWidth"] <= audit["limit"] + 1,
                  f"(scrollWidth={audit['pageScrollWidth']})")
            for t in audit["tables"]:
                check(f"table#{t['table']} fits page ({t['width']}px, left={t['left']}, right={t['right']})",
                      t["fits"])
                lh = t["lastHeader"]
                if lh:
                    last_in = lh["left"] >= -0.5 and lh["right"] <= audit["limit"] + 0.5
                    check(f"table#{t['table']} last column «{lh['text']}» fully inside", last_in,
                          f"(left={lh['left']}, right={lh['right']})")
                    print(f"    columns: {[h['text'] for h in t['headers']]}")

            # ---- real PDF honoring @page CSS ----
            pdf_path = os.path.join(OUT, f"{name}.pdf")
            page.pdf(path=pdf_path, prefer_css_page_size=True)
            print(f"  pdf -> {pdf_path}")
            page.emulate_media(media="screen")
            page.set_viewport_size({"width": 1280, "height": 900})

        browser.close()

    print()
    if FAILURES:
        print(f"RESULT: {len(FAILURES)} FAILURES -> {FAILURES}")
        sys.exit(1)
    print("RESULT: ALL PASS")


if __name__ == "__main__":
    main()
