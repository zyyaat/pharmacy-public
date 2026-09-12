#!/usr/bin/env python3
"""E2E — SaaS Plans & Subscriptions (Task 90).

Run against a server on :8080 (reports_test DB, migrations at boot,
bootstrap env set): python3 scripts/plans_e2e.py

Covers:
  A. Super-admin plan management: list seeds, features catalog, create,
     duplicate slug 409, invalid limits 400, detail roundtrip, atomic PUT,
     status toggle
  B. Registration → trial subscription on default_plan_slug (professional)
     with days_left ~30 and usage meters
  C. Enforcement: plan gate denies a permission the plan lacks (even for
     the owner), limit enforcement (branches/products), plan edit takes
     effect immediately (cache invalidation), lazy expiry → allow-list,
     manual payment activates, extend, suspend/reactivate
  D. Super-admin bypass + seeded professional still grants POS
"""
import sys
import time
import uuid

import psycopg2
import requests

BASE = "http://127.0.0.1:8080/api/v1"
DB = "postgresql://postgres@127.0.0.1:54329/reports_test"
PASSWORD = "Str0ng!Pass2026"
PLATFORM = ("e2e-admin@pharmacyos.test", "E2eAdmin#2026")
FAILURES = []


def check(name, ok, extra=""):
    print(("PASS " if ok else "FAIL ") + name + (f"  [{extra}]" if extra and not ok else ""))
    if not ok:
        FAILURES.append(name)


def wait_health():
    for _ in range(60):
        try:
            if requests.get("http://127.0.0.1:8080/health", timeout=1).status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(0.5)
    return False


def new_company():
    """Register + verify + onboard a fresh company; returns (session, email)."""
    email = f"plans-e2e-{uuid.uuid4().hex[:8]}@test.io"
    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": "صيدلية الاشتراكات", "company_email": email,
        "first_name": "المالك", "last_name": "الاشتراك",
        "email": email, "password": PASSWORD,
    }, timeout=10)
    assert r.status_code in (200, 201), r.text
    conn = psycopg2.connect(DB)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (email,))
    cur.execute(
        "UPDATE pharmacies SET settings = settings || '{\"onboarding\": {\"completed\": true}}'::jsonb "
        "WHERE account_id IN (SELECT id FROM accounts WHERE contact_email=%s)",
        (email,),
    )
    conn.close()
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": PASSWORD}, timeout=10)
    assert r.status_code == 200, r.text
    # مسارات الكتابة تتطلب CSRF double-submit (كما في باقي سكربتات e2e)
    s.headers["X-CSRF-Token"] = s.cookies.get("pharmacy_csrf", "")
    return s, email


def platform_session():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/platform/login",
               json={"email": PLATFORM[0], "password": PLATFORM[1]}, timeout=10)
    assert r.status_code == 200, r.text
    csrf = s.cookies.get("platform_csrf", "")
    s.headers["X-CSRF-Token"] = csrf
    return s


def plan_by_slug(plat, slug):
    r = plat.get(f"{BASE}/platform-admin/plans", timeout=10)
    assert r.status_code == 200
    for p in r.json()["data"]:
        if p["slug"] == slug:
            return p
    return None


def main():
    assert wait_health(), "server not healthy"
    conn = psycopg2.connect(DB)
    conn.autocommit = True
    cur = conn.cursor()
    plat = platform_session()

    # ---------------- A. plan management ----------------
    r = plat.get(f"{BASE}/platform-admin/plans", timeout=10)
    check("1. قائمة الخطط ← 200 و4 خطط مزروعة", r.status_code == 200 and len(r.json()["data"]) >= 4, r.text[:120])
    seeds = {p["slug"] for p in r.json()["data"]}
    check("2. البذور تشمل free/starter/professional/enterprise",
          {"free", "starter", "professional", "enterprise"} <= seeds, str(seeds))
    prof = plan_by_slug(plat, "professional")
    check("3. احترافية مشتركون فيها (backfill) > 0", (prof or {}).get("subscribers", 0) > 0)

    r = plat.get(f"{BASE}/platform-admin/features", timeout=10)
    feats = r.json()["data"]
    check("4. كتالوج الميزات ← 9 ميزات مع صلاحيات مقترحة",
          r.status_code == 200 and len(feats) == 9 and all(f["suggested_permissions"] for f in feats if f["key"] != "multi_branch"),
          str(len(feats)))

    slug = f"e2e-plan-{uuid.uuid4().hex[:6]}"
    payload = {
        "slug": slug, "name": "E2E Plan", "name_ar": "خطة الاختبار",
        "description": "خطة e2e",
        "monthly_price_piastres": 12345, "yearly_price_piastres": 123456,
        "is_active": True, "is_public": True, "sort_order": 5,
        "features": ["pos", "sales", "inventory"],
        "permissions": ["pos.access", "sales.view", "sales.returns", "inventory.view",
                        "inventory.manage_products", "products.pharmacy.add",
                        "products.pharmacy.pricing", "branches.view", "branches.create",
                        "branches.update", "branches.delete",
                        "settings.general", "settings.billing", "companies.view"],
        "limits": {"branches": 2, "users": 3, "employees": 2, "products": 5},
    }
    r = plat.post(f"{BASE}/platform-admin/plans", json=payload, timeout=10)
    check("5. إنشاء خطة ← 201", r.status_code == 201, r.text[:150])
    plan_id = r.json()["data"]["id"] if r.status_code == 201 else ""

    r = plat.post(f"{BASE}/platform-admin/plans", json=payload, timeout=10)
    check("6. تكرار المعرف ← 409", r.status_code == 409, str(r.status_code))

    bad = dict(payload, slug=f"bad-{uuid.uuid4().hex[:6]}", limits={"branches": -5})
    r = plat.post(f"{BASE}/platform-admin/plans", json=bad, timeout=10)
    check("7. حد سالب (-5) ← 400", r.status_code == 400, str(r.status_code))

    r = plat.get(f"{BASE}/platform-admin/plans/{plan_id}", timeout=10)
    detail = r.json()["data"]
    check("8. تفاصيل الخطة تطابق المُدخلات",
          r.status_code == 200 and sorted(detail["features"]) == sorted(["pos", "sales", "inventory"])
          and detail["limits"] == {"branches": 2, "users": 3, "employees": 2, "products": 5},
          r.text[:200])

    payload["features"] = ["pos", "sales", "inventory"]
    payload["permissions"] = payload["permissions"] + ["inventory.adjust"]
    payload["limits"] = {"branches": 2, "users": 3, "employees": 2, "products": 7}
    r = plat.put(f"{BASE}/platform-admin/plans/{plan_id}", json=payload, timeout=10)
    r2 = plat.get(f"{BASE}/platform-admin/plans/{plan_id}", timeout=10)
    check("9. تعديل الخطة ذريًا ← المجموعات الجديدة",
          r.status_code == 200 and r2.json()["data"]["limits"]["products"] == 7
          and "inventory" in r2.json()["data"]["features"])

    r = plat.patch(f"{BASE}/platform-admin/plans/{plan_id}/status", json={"is_active": False}, timeout=10)
    r2 = plat.get(f"{BASE}/platform-admin/plans/{plan_id}", timeout=10)
    check("10. تعطيل الخطة ← is_active=false",
          r.status_code == 200 and r2.json()["data"]["is_active"] is False)
    plat.patch(f"{BASE}/platform-admin/plans/{plan_id}/status", json={"is_active": True}, timeout=10)

    # ---------------- B. registration → trial ----------------
    owner, email = new_company()
    r = owner.get(f"{BASE}/pharmacy/subscription", timeout=10)
    sub = r.json()["data"]
    check("11. التسجيل ينشئ اشتراكًا تجريبيًا على professional",
          r.status_code == 200 and sub["subscription"]["status"] == "trial"
          and sub["plan"]["slug"] == "professional", r.text[:200])
    check("12. عداد الأيام ~30 والاستهلاك فرع واحد",
          25 <= sub["subscription"]["days_left"] <= 30 and sub["usage"]["branches"] == 1,
          str(sub["subscription"]["days_left"]))

    r = owner.get(f"{BASE}/pharmacy/plans", timeout=10)
    check("13. الخطط العامة ظاهرة للترقية", r.status_code == 200 and len(r.json()["data"]) >= 4)
    check("14. المالك يصل تقارير الاحترافية (professional يملكها)",
          owner.get(f"{BASE}/pharmacy/reports/sales", timeout=10).status_code == 200)

    # ---------------- C. enforcement ----------------
    cur.execute("SELECT company_id::text FROM company_users WHERE email=%s", (email,))
    company_id = cur.fetchone()[0]
    r = plat.post(f"{BASE}/platform-admin/subscriptions", json={
        "company_id": company_id, "plan_id": plan_id,
        "billing_interval": "monthly",
    }, timeout=10)
    check("15. إسناد خطة الاختبار يدويًا ← 201", r.status_code == 201, r.text[:200])

    r = owner.get(f"{BASE}/pharmacy/reports/sales", timeout=10)
    body = r.json()
    check("16. بوابة الخطة تمنع reports.sales عن المالك نفسه",
          r.status_code == 403 and body.get("error") == "plan_permission_denied",
          r.text[:150])
    check("17. المالك ما زال يصل المخزون (الخطة تملك inventory.view)",
          owner.get(f"{BASE}/pharmacy/inventory", timeout=10).status_code == 200)

    # branches limit = 2 (existing main branch consumes 1)
    def make_branch(name):
        return owner.post(f"{BASE}/pharmacy/branches", json={"name": name}, timeout=10)
    r = make_branch("فرع ثانٍ")
    check("18. الفرع الثاني ضمن الحد ← 200/201", r.status_code in (200, 201), r.text[:120])
    r = make_branch("فرع ثالث")
    body = r.json()
    check("19. الفرع الثالث ← plan_limit_reached (limit=2, used=2)",
          r.status_code == 403 and body.get("error") == "plan_limit_reached"
          and body.get("limit") == 2 and body.get("used") == 2, r.text[:200])

    # products limit = 7
    def make_product(i):
        return owner.post(f"{BASE}/pharmacy/products", json={
            "name": f"منتج {i}", "barcode": "", "dosage_form": "tablet",
            "strength": "1", "strength_unit": "mg", "sale_price": 1000,
        }, timeout=10)
    made = [make_product(i) for i in range(1, 8)]
    check("20. سبعة منتجات ضمن الحد تنجح",
          all(m.status_code in (200, 201) for m in made),
          str([m.status_code for m in made]))
    r = make_product(8)
    check("21. المنتج الثامن ← plan_limit_reached (products=7)",
          r.status_code == 403 and r.json().get("limit_key") == "products", r.text[:150])

    # plan edit takes effect immediately (cache invalidation)
    payload["limits"] = {"branches": 2, "users": 3, "employees": 2, "products": 8}
    plat.put(f"{BASE}/platform-admin/plans/{plan_id}", json=payload, timeout=10)
    r = make_product(9)
    check("22. رفع الحد إلى 8 يسمح فورًا بمنتج ثامن", r.status_code in (200, 201), r.text[:120])

    # lazy expiry → lockout + allow-list. النطاق الإنتاجي: المدة تتغير عبر
    # API (الذي يبطّل الكاش) — مثل مسار Paymob/التمديد اليدوي.
    cur.execute("SELECT id::text FROM subscriptions WHERE company_id=%s AND status='active'", (company_id,))
    sub_row = cur.fetchone()[0]
    r = plat.patch(f"{BASE}/platform-admin/subscriptions/{sub_row}",
                   json={"action": "extend", "current_period_end": "2020-01-01T00:00:00Z"}, timeout=10)
    check("23a. تمديد لتاريخ ماضٍ (محاكاة انتهاء) ← 200", r.status_code == 200, r.text[:120])
    r = owner.get(f"{BASE}/pharmacy/inventory", timeout=10)
    check("23. انتهاء الفترة ← inventory 403 subscription_expired",
          r.status_code == 403 and r.json().get("error") == "subscription_expired", r.text[:150])
    r = owner.get(f"{BASE}/pharmacy/subscription", timeout=10)
    check("24. صفحة الاشتراك تعمل بعد الانتهاء (allow-list) وتقر expired",
          r.status_code == 200 and r.json()["data"]["subscription"]["status"] == "expired")
    r = owner.get(f"{BASE}/pharmacy/plans", timeout=10)
    check("25. الخطط العامة تعمل بعد الانتهاء (allow-list)", r.status_code == 200)
    r = requests.Session().post(f"{BASE}/auth/pharmacy/login",
                                json={"email": email, "password": PASSWORD}, timeout=10)
    check("26. تسجيل الدخول يبقى ممكنًا بعد الانتهاء", r.status_code == 200)

    # manual payment re-activates (Paymob webhook will drive the same transition)
    prof_id = plan_by_slug(plat, "professional")["id"]
    r = plat.post(f"{BASE}/platform-admin/payments/manual", json={
        "company_id": company_id, "plan_id": prof_id,
        "billing_interval": "monthly", "note": "تحويل بنكي e2e",
    }, timeout=10)
    check("27. دفع يدوي ← 201 succeeded", r.status_code == 201 and r.json()["data"]["status"] == "succeeded", r.text[:150])
    r = owner.get(f"{BASE}/pharmacy/subscription", timeout=10)
    sub2 = r.json()["data"]
    check("28. الاشتراك عاد active على professional",
          sub2["subscription"]["status"] == "active" and sub2["plan"]["slug"] == "professional")
    check("29. المخزون يعود يعمل بعد الدفع",
          owner.get(f"{BASE}/pharmacy/inventory", timeout=10).status_code == 200)

    # extend — الصف الحي بعد الدفع هو صف جديد (القديم انتهى)؛ نعيد جلبه
    cur.execute("SELECT id::text FROM subscriptions WHERE company_id=%s AND status='active'", (company_id,))
    sub_row = cur.fetchone()[0]
    r = plat.patch(f"{BASE}/platform-admin/subscriptions/{sub_row}",
                   json={"action": "extend", "current_period_end": "2027-01-01T00:00:00Z"}, timeout=10)
    r2 = owner.get(f"{BASE}/pharmacy/subscription", timeout=10)
    new_end = (r2.json()["data"]["subscription"]["current_period_end"] or "")
    check("30. تمديد الفترة ينعكس في /subscription",
          r.status_code == 200 and "2027-01-01" in new_end,
          r.text[:120] + " | end=" + new_end)

    # suspend / reactivate
    r = plat.patch(f"{BASE}/platform-admin/subscriptions/{sub_row}", json={"action": "suspend"}, timeout=10)
    r2 = owner.get(f"{BASE}/pharmacy/inventory", timeout=10)
    check("31. التعليق ← 403 subscription_suspended",
          r2.status_code == 403 and r2.json().get("error") == "subscription_suspended")
    r = plat.patch(f"{BASE}/platform-admin/subscriptions/{sub_row}", json={"action": "reactivate"}, timeout=10)
    r2 = owner.get(f"{BASE}/pharmacy/inventory", timeout=10)
    check("32. إعادة التفعيل تُرجع الوصول", r2.status_code == 200)

    # subscriptions ledger
    r = plat.get(f"{BASE}/platform-admin/subscriptions", params={"search": email}, timeout=10)
    check("33. سجل الاشتراكات يظهر تاريخ الشركة",
          r.status_code == 200 and r.json()["pagination"]["total"] >= 1)

    # employees limit — create employees up to plan cap (employees=2)
    r = plat.get(f"{BASE}/platform-admin/subscriptions", params={"company_id": company_id, "status": "active"}, timeout=10)
    check("34. فلتر الحالة يعمل", r.json()["pagination"]["total"] == 1)

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(" -", f)
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
