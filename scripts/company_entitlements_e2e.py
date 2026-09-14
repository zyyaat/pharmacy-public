#!/usr/bin/env python3
"""E2E — per-company account page + entitlement overrides (Task 15).

Run against a server on :8080 (reports_test DB, migrations at boot,
bootstrap env set): python3 scripts/company_entitlements_e2e.py

Covers:
  A. Profile endpoint: governing subscription + plan + usage + counts
  B. Entitlement validation (unknown keys, invalid kind/value, missing
     enabled) — bad inputs 400
  C. Feature GRANT bundles its derived permissions: reports granted on a
     starter company → module appears in the payload AND its API works
     (the Task-13 drift cannot reproduce per-account)
  D. Feature DENY bundles: inventory denied on starter → hidden from the
     payload AND the API answers plan_permission_denied
  E. Limit override: products ceiling 5000 → 2 blocks the 3rd product;
     -1 (unlimited) unblocks immediately (cache invalidated)
  F. Expiry: override with a past expires_at is ignored (self-reversing)
  G. DELETE cascade: removing the inventory deny falls feature + bundled
     permissions back to the plan baseline immediately
  H. Per-account logs: platform_audit_logs.company_id hard filter +
     legacy platform actions now audited at all (silent-loss fix)
"""
import json
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


def platform_session():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/platform/login",
               json={"email": PLATFORM[0], "password": PLATFORM[1]}, timeout=10)
    assert r.status_code == 200, r.text
    s.headers["X-CSRF-Token"] = s.cookies.get("platform_csrf", "")
    return s


def new_company(plan_slug):
    """Register + verify + minimal pharmacy + assign plan; returns (session, company_id)."""
    email = f"entl-e2e-{uuid.uuid4().hex[:8]}@test.io"
    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": "صيدلية الاستثناءات", "company_email": email,
        "first_name": "المالك", "last_name": "الاستثناء",
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
    cur.execute("SELECT company_id FROM company_users WHERE email = %s", (email,))
    company_id = str(cur.fetchone()[0])
    conn.close()

    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": PASSWORD}, timeout=10)
    assert r.status_code == 200, r.text
    s.headers["X-CSRF-Token"] = s.cookies.get("pharmacy_csrf", "")

    plat = platform_session()
    plan_id = None
    for p in plat.get(f"{BASE}/platform-admin/plans", timeout=10).json()["data"]:
        if p["slug"] == plan_slug:
            plan_id = p["id"]
    assert plan_id, f"plan {plan_slug} missing"
    r = plat.post(f"{BASE}/platform-admin/subscriptions",
                  json={"company_id": str(company_id), "plan_id": plan_id,
                        "billing_interval": "monthly"}, timeout=10)
    assert r.status_code == 201, r.text
    return s, str(company_id)


def payload(sess):
    r = sess.get(f"{BASE}/pharmacy/subscription", timeout=10)
    assert r.status_code == 200, r.text
    return r.json()["data"]


def grant(plat, company_id, body, expect=201):
    r = plat.post(f"{BASE}/platform-admin/companies/{company_id}/entitlements",
                  json=body, timeout=10)
    assert r.status_code == expect, f"{body} → {r.status_code} {r.text[:200]}"
    return r


def make_product(sess, i):
    return sess.post(f"{BASE}/pharmacy/products", json={
        "name": f"منتج {i}", "barcode": "", "dosage_form": "tablet",
        "strength": "1", "strength_unit": "mg", "sale_price": 1000,
    }, timeout=10)


def main():
    assert wait_health(), "server not healthy"
    plat = platform_session()

    # ---------------- A. Profile endpoint ----------------
    sess_s, company_s = new_company("starter")
    r = plat.get(f"{BASE}/platform-admin/companies/{company_s}", timeout=10)
    check("A1 profile 200", r.status_code == 200, r.text[:120])
    prof = r.json()["data"]
    check("A2 governing subscription starter/active",
          prof["subscription"]["plan"]["slug"] == "starter"
          and prof["subscription"]["status"] == "active",
          json.dumps(prof.get("subscription", {}), ensure_ascii=False)[:160])
    check("A3 usage meters present", isinstance(prof.get("usage"), dict)
          and "products" in prof["usage"], str(prof.get("usage")))
    check("A4 active_overrides = 0 initially", prof.get("active_overrides") == 0)
    r = plat.get(f"{BASE}/platform-admin/companies/00000000-0000-0000-0000-000000000000", timeout=10)
    check("A5 unknown company 404", r.status_code == 404, str(r.status_code))

    # ---------------- B. Validation ----------------
    checks = [
        ("B1 unknown feature key", {"kind": "feature", "key": "no-such-feat", "enabled": True}),
        ("B2 unknown permission key", {"kind": "permission", "key": "no.such.perm", "enabled": True}),
        ("B3 unknown limit key", {"kind": "limit", "key": "no_such", "value": 5}),
        ("B4 invalid kind", {"kind": "plan", "key": "x"}),
        ("B5 limit value 0 invalid", {"kind": "limit", "key": "products", "value": 0}),
        ("B6 feature missing enabled", {"kind": "feature", "key": "reports"}),
    ]
    for name, body in checks:
        r = plat.post(f"{BASE}/platform-admin/companies/{company_s}/entitlements",
                      json=body, timeout=10)
        check(name + " → 400", r.status_code == 400, f"{r.status_code} {r.text[:100]}")

    # ---------------- C. Feature GRANT bundle ----------------
    before = payload(sess_s)
    check("C0 baseline: starter payload lacks reports",
          "reports" not in before["plan"]["features"], str(before["plan"]["features"]))
    grant(plat, company_s, {"kind": "feature", "key": "reports", "enabled": True,
                            "reason": "تجربة شهر مجاني"})
    after = payload(sess_s)
    check("C1 granted feature appears immediately (cache invalidated)",
          "reports" in after["plan"]["features"], str(after["plan"]["features"]))
    r = sess_s.get(f"{BASE}/pharmacy/reports/sales", timeout=10)
    check("C2 bundled permission works in API (reports.sales no longer 403)",
          r.status_code == 200, f"{r.status_code} {r.text[:120]}")

    # ---------------- E. Limit override (BEFORE the inventory deny: the
    # deny-bundle blocks products.pharmacy.add, so limits must be tested
    # while permissions are intact) ----------------
    grant(plat, company_s, {"kind": "limit", "key": "products", "value": 2})
    m1, m2, m3 = make_product(sess_s, 1), make_product(sess_s, 2), make_product(sess_s, 3)
    check("E1 first two products within override ceiling",
          m1.status_code in (200, 201) and m2.status_code in (200, 201),
          f"{m1.status_code}/{m2.status_code}")
    check("E2 third product → plan_limit_reached (limit=2)",
          m3.status_code == 403 and m3.json().get("error") == "plan_limit_reached"
          and m3.json().get("limit") == 2, f"{m3.status_code} {m3.text[:160]}")
    grant(plat, company_s, {"kind": "limit", "key": "products", "value": -1})
    m4 = make_product(sess_s, 4)
    check("E3 unlimited override applies immediately",
          m4.status_code in (200, 201), f"{m4.status_code} {m4.text[:120]}")

    # ---------------- D. Feature DENY bundle ----------------
    grant(plat, company_s, {"kind": "feature", "key": "inventory", "enabled": False,
                            "reason": "حساب معلّق مؤقتًا"})
    after = payload(sess_s)
    check("D1 denied feature hidden from payload",
          "inventory" not in after["plan"]["features"], str(after["plan"]["features"]))
    r = sess_s.get(f"{BASE}/pharmacy/inventory", timeout=10)
    check("D2 denied feature blocks API too (plan_permission_denied)",
          r.status_code == 403 and r.json().get("error") == "plan_permission_denied",
          f"{r.status_code} {r.text[:120]}")

    # ---------------- F. Expiry (self-reversing grants) ----------------
    # One row per (company, kind, key): upserting the PAST-EXPIRED grant
    # replaces the live one. If expiry were NOT respected, the grant would
    # still lift reports above the starter baseline — its absence proves
    # the expired row is ignored (back to baseline).
    grant(plat, company_s, {"kind": "feature", "key": "reports", "enabled": True,
                            "expires_at": "2001-01-01T00:00:00Z"})
    r = plat.get(f"{BASE}/platform-admin/companies/{company_s}/entitlements", timeout=10)
    rows = r.json()["data"]
    expired = [x for x in rows if x["expired"]]
    check("F1 expired rows listed with expired flag", len(expired) >= 1,
          str([(x['kind'], x['key']) for x in expired]))
    check("F2 expired grant ignored → reports back to plan baseline (absent)",
          "reports" not in payload(sess_s)["plan"]["features"],
          str(payload(sess_s)["plan"]["features"]))

    # ---------------- G. DELETE cascade ----------------
    grant(plat, company_s, {"kind": "feature", "key": "inventory", "enabled": False})
    rows = plat.get(f"{BASE}/platform-admin/companies/{company_s}/entitlements", timeout=10).json()["data"]
    inv = [x for x in rows if x["kind"] == "feature" and x["key"] == "inventory"][0]
    bundle_rows = [x for x in rows if x["bundle_key"] == "feature:inventory"]
    check("G1 deny bundle created permission rows", len(bundle_rows) >= 7, str(len(bundle_rows)))
    r = plat.delete(f"{BASE}/platform-admin/companies/{company_s}/entitlements/{inv['id']}", timeout=10)
    check("G2 delete 200", r.status_code == 200, r.text[:120])
    after = payload(sess_s)
    r = sess_s.get(f"{BASE}/pharmacy/inventory", timeout=10)
    check("G3 feature + bundle fell back to baseline (visible AND working)",
          "inventory" in after["plan"]["features"] and r.status_code == 200,
          f"{r.status_code} {after['plan']['features']}")

    # ---------------- H. Per-account logs ----------------
    r = plat.get(f"{BASE}/platform-admin/companies/{company_s}/logs", timeout=10)
    check("H1 logs endpoint 200", r.status_code == 200, r.text[:120])
    actions = [x["action"] for x in r.json()["data"]]
    check("H2 assign audited (silent-loss fix)", "subscription.assign" in actions, str(actions[:10]))
    check("H3 entitlement.feature audited", "entitlement.feature" in actions, str(actions[:10]))
    check("H4 entitlement.limit audited", "entitlement.limit" in actions, str(actions[:10]))
    check("H5 entitlement.remove audited", "entitlement.remove" in actions, str(actions[:10]))

    # isolation: a second company's log contains only its own events
    sess_p, company_p = new_company("professional")
    grant(plat, company_p, {"kind": "permission", "key": "inventory.view", "enabled": False,
                            "reason": "منع فردي"})
    r = plat.get(f"{BASE}/platform-admin/companies/{company_p}/logs", timeout=10)
    p_actions = [x["action"] for x in r.json()["data"]]
    check("H6 second company logs isolated (own assign + own override only)",
          "subscription.assign" in p_actions and "entitlement.permission" in p_actions
          and "entitlement.feature" not in p_actions, str(p_actions[:12]))
    r = sess_p.get(f"{BASE}/pharmacy/inventory", timeout=10)
    check("H7 individual permission deny → API 403 on professional",
          r.status_code == 403 and r.json().get("error") == "plan_permission_denied",
          f"{r.status_code} {r.text[:120]}")

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)} → {FAILURES}")
        sys.exit(1)
    print("ALL PASS — company account page + entitlement overrides")


if __name__ == "__main__":
    main()
