#!/usr/bin/env python3
"""POS smart-search verification (Task 32).

Covers:
  - name prefix / substring search (professional dropdown data source)
  - 1-char typo via trigram:      كاربيمازول ← كاربيمازون
  - heavy garbling via tier-2:    كاربيمازول ← كانبيبالول
  - barcode exact / prefix / misread (transposed + missing digit)
  - pharmacy scoping, 400s, limit clamp, generic-name fuzzy
  - speed sanity: p95 of search calls on a realistic catalog

Requires: backend :8080 against reports_test (migration 17 applied on boot),
login print-test@test.io / Str0ng!Pass2026
"""
import sys
import time

import requests

BASE = "http://127.0.0.1:8080/api/v1"
EMAIL = "print-test@test.io"
PASSWORD = "Str0ng!Pass2026"

FAILURES = []


def check(name, cond, detail=""):
    print(f"  [{'PASS' if cond else 'FAIL'}] {name} {detail}")
    if not cond:
        FAILURES.append(name)


def main():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": EMAIL, "password": PASSWORD}, timeout=10)
    check("login", r.status_code == 200, r.status_code)
    csrf = s.cookies.get("pharmacy_csrf")
    post_headers = {"X-CSRF-Token": csrf} if csrf else {}

    def search(q, limit=None):
        params = {"q": q}
        if limit:
            params["limit"] = str(limit)
        return s.get(f"{BASE}/pharmacy/pos/search", params=params, timeout=10)

    def names(payload):
        return [item["name"] for item in payload["data"]]

    # ---------- seed products ----------
    print("== seed ==")
    seeds = [
        # (name, generic, barcode)
        ("كاربيمازول 200mg", "كاربيمازين", "6221031500011"),
        ("كاربيمازين CR 400", "كاربيمازين", "6221031500028"),
        ("بانادول اكسترا", "باراسيتامول", "6221004000012"),
        ("كونجستال", "سودوافدرين", "6221048000013"),
        ("أوجمنتين 1g", "أموكسيسيلين/كلافولانيك", "6221031500035"),
    ]
    for name, generic, barcode in seeds:
        body = {
            "name": name, "generic_name": generic, "dosage_form": "tablet",
            "strength": "500mg", "barcode": barcode, "packaging_type": "BOX_STRIP",
            "units_per_box": 2, "cost_price_piastres": 4000,
            "selling_price_piastres": 6500, "partial_selling_price_piastres": 3500,
            "min_stock_level": 2, "initial_boxes": 5, "initial_strips": 3,
            "batch_number": f"B-{barcode[-4:]}",
        }
        r = s.post(f"{BASE}/pharmacy/products", headers=post_headers, json=body, timeout=10)
        if r.status_code == 409:
            print(f"  [SKIP] {name} موجود مسبقاً")
        else:
            check(f"seed {name}", r.status_code == 201, f"{r.status_code} {r.text[:80]}")

    # ---------- 1) name search (prefix + substring) ----------
    print("== name search ==")
    r = search("كاربيما")
    check("prefix كاربيما → 200 + 200mg", r.status_code == 200 and any("كاربيمازول" in n for n in names(r.json())), names(r.json())[:3] if r.status_code == 200 else r.text[:80])
    if r.status_code == 200:
        kinds = {i["match_type"] for i in r.json()["data"]}
        check("match_type name_prefix موجود", "name_prefix" in kinds, kinds)

    r = search("بانادول اكس")
    check("substring متعدد الكلمات", r.status_code == 200 and any("بانادول" in n for n in names(r.json())))

    r = search("200mg")
    check("بحث بجزء الجرعة", r.status_code == 200 and any("كاربيمازول" in n for n in names(r.json())))

    # ---------- 2) trigram typo (1-char) ----------
    print("== trigram typos ==")
    r = search("كاربيمازون")
    data = r.json().get("data", []) if r.status_code == 200 else []
    check("كاربيمازون → كاربيمازول", any("كاربيمازول" in n for n in names({"data": data})), [ (i["name"], i["match_type"], round(i["score"],2)) for i in data[:2] ])

    r = search("باراسيتامول")
    check("المادة الفعالة بالاسم الكامل", r.status_code == 200 and any("بانادول" in n for n in names(r.json())))

    # ---------- 3) heavy garbling (tier-2 levenshtein) ----------
    print("== tier-2 garbling ==")
    t0 = time.perf_counter()
    r = search("كانبيبالول")
    dt = (time.perf_counter() - t0) * 1000
    data = r.json().get("data", []) if r.status_code == 200 else []
    check("كانبيبالول → كاربيمازول (3 أخطاء)", any("كاربيمازول" in n for n in names({"data": data})), [(i["name"], i["match_type"], round(i["score"], 2)) for i in data[:2]])
    check(f"زمن الاستجابة معقول ({dt:.0f}ms)", dt < 800, f"{dt:.0f}ms")

    # warm cache second call should be faster
    t0 = time.perf_counter()
    search("كانبيبالول")
    dt2 = (time.perf_counter() - t0) * 1000
    check(f"النداء الثاني أسرع (كاش الكتالوج) ({dt2:.0f}ms)", dt2 <= max(150, dt), f"{dt2:.0f}ms vs {dt:.0f}ms")

    # ---------- 4) barcode paths ----------
    print("== barcode ==")
    r = search("6221031500011")
    data = r.json().get("data", []) if r.status_code == 200 else []
    check("باركود تام → barcode_exact أولاً", bool(data) and data[0]["match_type"] == "barcode_exact" and "كاربيمازول" in data[0]["name"], [(i["name"], i["match_type"]) for i in data[:2]])

    r = search("6221031500")
    data = r.json().get("data", []) if r.status_code == 200 else []
    check("بادئة باركود (ماسح مقطوع)", any(i["match_type"] in ("barcode_prefix", "name_prefix") for i in data), [(i["name"], i["match_type"]) for i in data[:2]])

    r = search("6221031500101")  # transposed digits: 011→101
    data = r.json().get("data", []) if r.status_code == 200 else []
    check("باركود بأرقام مبادلة → تقريبي", any("كاربيمازول" in i["name"] and i["match_type"] in ("barcode_fuzzy", "barcode_exact") for i in data), [(i["name"], i["match_type"], round(i["score"], 2)) for i in data[:2]])

    r = search("622103150001")  # missing last digit
    data = r.json().get("data", []) if r.status_code == 200 else []
    check("باركود ناقص رقم → prefix/تقريبي", any("كاربيمازول" in i["name"] for i in data), [(i["name"], i["match_type"]) for i in data[:2]])

    # ---------- 5) validation & limits ----------
    print("== validation ==")
    r = search("ك")
    check("حرف واحد → 400", r.status_code == 400, r.status_code)
    r = search("")
    check("فارغ → 400", r.status_code == 400, r.status_code)
    r = search("كاربيمازول 200mg%")
    check("wildcards % لا تكسر الاستعلام", r.status_code == 200, r.status_code)
    r = search("كاربيمازول", limit=1)
    check("limit=1 يُحترم", r.status_code == 200 and len(r.json()["data"]) == 1)
    r = search("كاربيمازول", limit=500)
    check("limit فوق الحد يُقص للافتراضي (8)", r.status_code == 200 and len(r.json()["data"]) <= 8)

    # ---------- 6) response shape ----------
    r = search("كاربيمازول")
    item = r.json()["data"][0]
    required = {"id", "name", "generic_name", "barcode", "packaging_type", "units_per_box",
                "selling_price_piastres", "partial_selling_price_piastres", "stock", "match_type", "score"}
    check("شكل الاستجابة كامل", required.issubset(item.keys()), sorted(item.keys()))
    check("stock رقمي وصحيح", isinstance(item["stock"], int) and item["stock"] >= 0, item["stock"])

    # ---------- 7) no-auth guard ----------
    r = requests.get(f"{BASE}/pharmacy/pos/search", params={"q": "كاربيمازول"}, timeout=10)
    check("بدون جلسة → 401", r.status_code == 401, r.status_code)

    # ---------- 8) speed sanity ----------
    print("== speed sanity ==")
    queries = ["كار", "كاربيمازول", "كانبيبالول", "6221031500011", "بانادول", "أوجمنتين", "كونجست", "6221004"]
    times = []
    for q in queries:
        t0 = time.perf_counter()
        rr = search(q)
        times.append((time.perf_counter() - t0) * 1000)
        if rr.status_code != 200:
            check(f"speed query {q}", False, rr.status_code)
    times.sort()
    p95 = times[int(len(times) * 0.95) - 1] if times else 0
    check(f"p95 ≤ 120ms محلياً (p95={p95:.0f}ms)", p95 <= 120, f"{[f'{t:.0f}' for t in times]}")

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {FAILURES}")
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
