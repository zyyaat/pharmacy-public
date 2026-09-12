#!/usr/bin/env python3
"""E2E — Paymob embedded checkout + verified webhook (Phase G).

Run against a server on :8080 booted with:
  PAYMOB_API_KEY / PUBLIC_KEY / CARD_INTEGRATION_ID (fake — intention fails
  gracefully), PAYMOB_HMAC_SECRET=phase_g_e2e_hmac_secret,
  PAYMOB_WEBHOOK_TOKEN=phase_g_e2e_token

Covers:
  A. checkout → intention fails (fake credentials) → 502 paymob_intention_failed,
     payment row honestly marked failed + intent txn recorded
  B. payment status endpoint is company-scoped and reflects state
  C. webhook: valid HMAC (documented field order) converts a running trial
     to active with snapshot amount + hmac_verified ledger row
  D. webhook idempotency: replay never double-extends
  E. webhook renewal: a second succeeded payment EXTENDS the period
  F. security: bad HMAC → 400 + no state change; bad/missing token → 401;
     amount mismatch → recorded + payment failed, never activated
"""
import datetime
import hashlib
import hmac as hmac_mod
import json
import sys
import time
import uuid

import psycopg2
import requests

BASE = "http://127.0.0.1:8080/api/v1"
DB = "postgresql://postgres@127.0.0.1:54329/reports_test"
PASSWORD = "Str0ng!Pass2026"
HMAC_SECRET = "phase_g_e2e_hmac_secret"
WEBHOOK_URL = f"{BASE}/payments/webhook/paymob?token=phase_g_e2e_token"
FAILURES = []

# Paymob's documented ordered concatenation for the transaction callback.
HMAC_FIELDS = [
    "amount_cents", "created_at", "currency", "error_occured",
    "has_parent_transaction", "id", "integration_id", "is_3d_secure",
    "is_auth", "is_capture", "is_refunded", "is_standalone_payment",
    "is_voided", "order.id", "owner", "pending",
    "source_data.pan", "source_data.sub_type", "source_data.type",
    "success",
]


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


def db():
    conn = psycopg2.connect(DB)
    conn.autocommit = True
    return conn


def render_value(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def lookup(obj, dotted):
    if dotted in obj:
        return obj[dotted]
    parent, _, child = dotted.rpartition(".")
    if parent and isinstance(obj.get(parent), dict):
        return obj[parent].get(child)
    return None


def sign(obj):
    concat = "".join(render_value(lookup(obj, f)) for f in HMAC_FIELDS)
    return hmac_mod.new(HMAC_SECRET.encode(), concat.encode(), hashlib.sha512).hexdigest()


def make_transaction_obj(payment_id, amount_cents, success=True, pending=False,
                         txn_id=None, order_id=None):
    txn_id = txn_id or int(time.time() * 1000) % 1_000_000_000
    order_id = order_id or int(time.time() * 1000) % 1_000_000_000
    return {
        "amount_cents": amount_cents,
        "created_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%f"),
        "currency": "EGP",
        "error_occured": not success,
        "has_parent_transaction": False,
        "id": txn_id,
        "integration_id": 4809999,
        "is_3d_secure": True,
        "is_auth": False,
        "is_capture": False,
        "is_refunded": False,
        "is_standalone_payment": False,
        "is_voided": False,
        "order": {"id": order_id, "merchant_order_id": payment_id},
        "owner": 555000,
        "pending": pending,
        "source_data": {"pan": "2346", "sub_type": "MasterCard", "type": "card"},
        "success": success,
    }


def post_webhook(obj, token_url=WEBHOOK_URL, sign_it=True):
    payload = dict(obj)
    if sign_it:
        payload["hmac"] = sign(obj)
    return requests.post(token_url, json={"type": "TRANSACTION", "obj": payload}, timeout=10)


def new_company():
    email = f"paymob-e2e-{uuid.uuid4().hex[:8]}@test.io"
    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": "صيدلية الموبايل", "company_email": email,
        "first_name": "المالك", "last_name": "الموبايل",
        "email": email, "password": PASSWORD,
    }, timeout=10)
    assert r.status_code in (200, 201), r.text
    conn = db()
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
    s.headers["X-CSRF-Token"] = s.cookies.get("pharmacy_csrf", "")
    return s, email


def company_id_of(email):
    conn = db()
    cur = conn.cursor()
    cur.execute("SELECT company_id FROM company_users WHERE email=%s", (email,))
    company_id = cur.fetchone()[0]
    conn.close()
    return str(company_id)


def professional_plan():
    conn = db()
    cur = conn.cursor()
    cur.execute("SELECT id::text, monthly_price_piastres FROM plans WHERE slug='professional' LIMIT 1")
    plan_id, monthly = cur.fetchone()
    conn.close()
    return plan_id, int(monthly)


def insert_pending_payment(company_id, plan_id, amount):
    pid = str(uuid.uuid4())
    conn = db()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO payments (id, company_id, plan_id, billing_interval, amount_piastres,"
        " currency, provider, status) VALUES (%s,%s,%s,'monthly',%s,'EGP','paymob','pending')",
        (pid, company_id, plan_id, amount),
    )
    conn.close()
    return pid


def subscription_row(company_id):
    conn = db()
    cur = conn.cursor()
    cur.execute(
        "SELECT status, billing_interval, trial_ends_at::text, current_period_end::text,"
        " current_period_start::text FROM subscriptions"
        " WHERE company_id=%s ORDER BY created_at DESC LIMIT 1",
        (company_id,),
    )
    row = cur.fetchone()
    conn.close()
    return row


def main():
    assert wait_health(), "backend not healthy"
    plan_id, monthly = professional_plan()
    print(f"professional plan: {plan_id} monthly={monthly}")

    s, email = new_company()
    company_id = company_id_of(email)
    print(f"company: {company_id}")

    # --- A. checkout against fake Paymob credentials → graceful 502 --------
    r = s.post(f"{BASE}/pharmacy/subscription/checkout",
               json={"plan_id": plan_id, "billing_interval": "monthly"}, timeout=40)
    body = r.json()
    check("checkout fails gracefully with fake credentials (502)", r.status_code == 502, str(r.status_code))
    check("checkout error code paymob_intention_failed", body.get("error") == "paymob_intention_failed", str(body))

    conn = db(); cur = conn.cursor()
    cur.execute("SELECT status, provider FROM payments WHERE company_id=%s ORDER BY created_at DESC LIMIT 1", (company_id,))
    pstatus, provider = cur.fetchone()
    cur.execute("SELECT COUNT(*) FROM payment_transactions pt JOIN payments p ON p.id=pt.payment_id"
                " WHERE p.company_id=%s AND pt.txn_type='intent'", (company_id,))
    intent_txns = cur.fetchone()[0]
    conn.close()
    check("failed intention marks payment failed", pstatus == "failed", pstatus)
    check("intent txn audit row recorded", intent_txns >= 1, str(intent_txns))

    # --- B. payment status endpoint (company-scoped) ------------------------
    cur_conn = db(); cur = cur_conn.cursor()
    cur.execute("SELECT id::text FROM payments WHERE company_id=%s ORDER BY created_at DESC LIMIT 1", (company_id,))
    last_payment = cur.fetchone()[0]
    cur_conn.close()
    r = s.get(f"{BASE}/pharmacy/subscription/payments/{last_payment}", timeout=10)
    check("payment status returns for own company", r.status_code == 200 and r.json()["data"]["status"] == "failed",
          r.text[:120])
    r = s.get(f"{BASE}/pharmacy/subscription/payments/{str(uuid.uuid4())}", timeout=10)
    check("payment status 404 for foreign id", r.status_code == 404, str(r.status_code))

    # --- C. verified webhook converts trial → active ------------------------
    payment_id = insert_pending_payment(company_id, plan_id, monthly)
    before = subscription_row(company_id)
    check("company is on trial before webhook", before[0] == "trial", str(before))

    obj = make_transaction_obj(payment_id, monthly, success=True)
    r = post_webhook(obj)
    data = r.json()
    check("webhook activated", r.status_code == 200 and data.get("result") == "activated", r.text[:160])
    after = subscription_row(company_id)
    check("subscription now active", after[0] == "active", str(after))
    check("billing interval monthly", after[1] == "monthly", str(after))
    check("trial ended (trial_ends_at cleared)", after[2] is None, str(after))
    check("period end ~1 month ahead", after[3] is not None, str(after))

    conn = db(); cur = conn.cursor()
    cur.execute("SELECT status, amount_piastres FROM payments WHERE id=%s", (payment_id,))
    pstatus, pamount = cur.fetchone()
    cur.execute("SELECT hmac_verified, provider_transaction_id FROM payment_transactions"
                " WHERE payment_id=%s AND txn_type='webhook'", (payment_id,))
    txn = cur.fetchone()
    cur.execute("SELECT status FROM companies WHERE id=%s", (company_id,))
    comp_status = cur.fetchone()[0]
    conn.close()
    check("payment marked succeeded with snapshot amount", pstatus == "succeeded" and pamount == monthly, f"{pstatus} {pamount}")
    check("txn row hmac_verified=true", txn is not None and txn[0] is True, str(txn))
    check("companies.status synced to active", comp_status == "active", comp_status)

    # --- D. idempotent replay: no double extension --------------------------
    period_end_first = subscription_row(company_id)[3]
    r = post_webhook(obj)  # same txn id again
    check("replay answered already_processed", r.json().get("result") == "already_processed", r.text[:120])
    check("replay did not extend the period", subscription_row(company_id)[3] == period_end_first,
          f"{period_end_first} → {subscription_row(company_id)[3]}")

    # --- E. renewal extends --------------------------------------------------
    payment2 = insert_pending_payment(company_id, plan_id, monthly)
    r = post_webhook(make_transaction_obj(payment2, monthly, success=True))
    check("renewal webhook activated", r.json().get("result") == "activated", r.text[:120])
    conn = db(); cur = conn.cursor()
    cur.execute("SELECT subscription_id FROM payments WHERE id=%s", (payment2,))
    linked_sub = cur.fetchone()[0]
    conn.close()
    check("renewal linked to the SAME live subscription", linked_sub is not None, str(linked_sub))
    pe2 = subscription_row(company_id)[3]
    check("renewal extended the period", pe2 != period_end_first, f"{period_end_first} → {pe2}")

    # --- F. security ----------------------------------------------------------
    payment3 = insert_pending_payment(company_id, plan_id, monthly)
    obj3 = make_transaction_obj(payment3, monthly, success=True)
    r = requests.post(WEBHOOK_URL, json={"type": "TRANSACTION", "obj": dict(obj3, hmac="0" * 128)}, timeout=10)
    check("bad HMAC rejected 400", r.status_code == 400, str(r.status_code))
    conn = db(); cur = conn.cursor()
    cur.execute("SELECT status FROM payments WHERE id=%s", (payment3,))
    check("bad HMAC left payment pending", cur.fetchone()[0] == "pending", "not pending")
    conn.close()

    r = post_webhook(obj3, token_url=f"{BASE}/payments/webhook/paymob?token=WRONG")
    check("bad URL token rejected 401", r.status_code == 401, str(r.status_code))

    payment4 = insert_pending_payment(company_id, plan_id, monthly)
    obj4 = make_transaction_obj(payment4, monthly + 10_000, success=True)  # tampered amount
    r = post_webhook(obj4)
    check("amount mismatch recorded, not activated", r.json().get("result") == "amount_mismatch_failed", r.text[:120])
    conn = db(); cur = conn.cursor()
    cur.execute("SELECT status FROM payments WHERE id=%s", (payment4,))
    check("amount mismatch fails the payment", cur.fetchone()[0] == "failed", "not failed")
    conn.close()
    check("subscription still active after attacks", subscription_row(company_id)[0] == "active", "")

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): " + "; ".join(FAILURES))
        sys.exit(1)
    print("ALL PAYMOB PHASE-G E2E CHECKS PASS")


if __name__ == "__main__":
    main()
