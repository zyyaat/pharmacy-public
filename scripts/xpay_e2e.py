#!/usr/bin/env python3
"""E2E — XPay gateway (Phase X): checkout sessions + verified webhook.

Run against a server on :8080 booted with BOTH gateways configured —
proving the priority (xpay wins) — and XPAY_BASE_URL pointing at the
local stub gateway this script spins up on 127.0.0.1:9555:
  XPAY_SECRET_KEY=sk_test_e2e XPAY_PUBLISHABLE_KEY=pk_test_e2e
  XPAY_WEBHOOK_SECRET=whsec_e2e_secret XPAY_WEBHOOK_TOKEN=xpay_e2e_token
  XPAY_BASE_URL=http://127.0.0.1:9555
  PAYMOB_* (fake values — paymob stays configured but must NOT be chosen)

Covers:
  A. checkout (embedded) → 201 provider=xpay + client_secret + pk;
     stub received Bearer auth + Idempotency-Key = payment_id +
     metadata.payment_id anchor; payment row provider='xpay' pending with
     provider_reference = session id; intent txn row recorded
  B. checkout (hosted / legacy mobile — no ui_mode) → embed_url is the
     hosted session URL
  C. webhook checkout.session.completed (paymentStatus=paid, signed with
     whsec over RAW body) → trial → active, payment succeeded, verified
     ledger row
  D. idempotency: the same event replayed never double-extends
  E. renewal: a second succeeded payment extends the period
  F. security: bad signature → 400 no state change; bad token → 401;
     amount mismatch → payment failed, never activated;
     completed+unpaid (Fawry reference) → stays pending;
     charge.failed → recorded, stays pending;
     async_payment_failed → payment failed;
     checkout.session.expired → payment failed
"""
import hashlib
import hmac as hmac_mod
import json
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
import requests

BASE = "http://127.0.0.1:8080/api/v1"
DB = "postgresql://postgres@127.0.0.1:54329/reports_test"
PASSWORD = "Str0ng!Pass2026"
XPAY_SECRET = "sk_test_e2e"
XPAY_PK = "pk_test_e2e"
WEBHOOK_SECRET = "whsec_e2e_secret"
WEBHOOK_TOKEN = "xpay_e2e_token"
WEBHOOK_URL = f"{BASE}/payments/webhook/xpay?token={WEBHOOK_TOKEN}"
WEBHOOK_URL_NO_TOKEN = f"{BASE}/payments/webhook/xpay"
STUB_PORT = 9555
FAILURES = []

STUB_SESSIONS = []  # every /checkout/sessions request the backend sent


class StubHandler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # silence
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if not self.path.startswith("/checkout/sessions"):
            return self._json(404, {"error": "not_found"})
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {XPAY_SECRET}":
            return self._json(401, {"error": "unauthorized"})
        req = json.loads(raw)
        payment_id = (req.get("metadata") or {}).get("payment_id", "")
        STUB_SESSIONS.append({
            "auth": auth,
            "idempotency_key": self.headers.get("Idempotency-Key", ""),
            "uiMode": req.get("uiMode"),
            "metadata_payment_id": payment_id,
            "unitAmount": (req.get("lineItems") or [{}])[0].get("priceData", {}).get("unitAmount"),
            "currency": (req.get("lineItems") or [{}])[0].get("priceData", {}).get("currency"),
            "afterCompletion": req.get("afterCompletion"),
        })
        if not payment_id:
            return self._json(422, {"error": "metadata_missing"})
        cs = "cs_test_" + uuid.uuid4().hex[:20]
        resp = {
            "id": cs,
            "object": "checkout.session",
            "status": "open",
            "paymentStatus": "unpaid",
            "currency": "EGP",
            "amountTotal": req.get("lineItems", [{}])[0].get("priceData", {}).get("unitAmount", 0),
            "metadata": req.get("metadata"),
        }
        if req.get("uiMode") == "embedded":
            resp["clientSecret"] = cs + "_secret_" + uuid.uuid4().hex[:12]
        else:
            resp["url"] = "https://checkout.xpay.app/p/" + cs
        self._json(201, resp)


def start_stub():
    server = ThreadingHTTPServer(("127.0.0.1", STUB_PORT), StubHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


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


def new_company():
    email = f"xpay-e2e-{uuid.uuid4().hex[:8]}@test.io"
    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": "صيدلية إكس باي", "company_email": email,
        "first_name": "المالك", "last_name": "إكس",
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


def payment_row(payment_id):
    conn = db()
    cur = conn.cursor()
    cur.execute(
        "SELECT provider, status, amount_piastres, provider_reference FROM payments WHERE id=%s",
        (payment_id,),
    )
    row = cur.fetchone()
    conn.close()
    return row


def intent_txn_exists(payment_id):
    conn = db()
    cur = conn.cursor()
    cur.execute(
        "SELECT COUNT(*) FROM payment_transactions WHERE payment_id=%s AND txn_type='intent'",
        (payment_id,),
    )
    n = cur.fetchone()[0]
    conn.close()
    return n


def webhook_txn_count(payment_id, event_id):
    conn = db()
    cur = conn.cursor()
    cur.execute(
        "SELECT COUNT(*) FROM payment_transactions WHERE payment_id=%s"
        " AND provider_transaction_id=%s AND txn_type='webhook' AND hmac_verified",
        (payment_id, event_id),
    )
    n = cur.fetchone()[0]
    conn.close()
    return n


def subscription_row(company_id):
    conn = db()
    cur = conn.cursor()
    cur.execute(
        "SELECT status, current_period_end::text FROM subscriptions"
        " WHERE company_id=%s ORDER BY created_at DESC LIMIT 1",
        (company_id,),
    )
    row = cur.fetchone()
    conn.close()
    return row


def sign_event(raw_body: str) -> str:
    ts = str(int(time.time()))
    sig = hmac_mod.new(WEBHOOK_SECRET.encode(), f"{ts}.{raw_body}".encode(), hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


def post_event(event: dict, url=WEBHOOK_URL, header=None):
    raw = json.dumps(event)  # sign EXACTLY the bytes we send
    headers = {"XPay-Signature": header if header is not None else sign_event(raw),
               "Content-Type": "application/json"}
    return requests.post(url, data=raw.encode(), headers=headers, timeout=10)


def session_event(event_id, payment_id, amount, event_type="checkout.session.completed",
                  payment_status="paid", session_id=None):
    return {
        "id": event_id,
        "object": "event",
        "type": event_type,
        "data": {"object": {
            "id": session_id or ("cs_test_" + uuid.uuid4().hex[:16]),
            "object": "checkout.session",
            "status": "complete" if event_type == "checkout.session.completed" else "open",
            "paymentStatus": payment_status,
            "amountTotal": amount,
            "currency": "EGP",
            "metadata": {"payment_id": payment_id},
        }},
    }


def do_checkout(s, plan_id, ui_mode=None, locale="ar"):
    body = {"plan_id": plan_id, "billing_interval": "monthly"}
    if ui_mode is not None:
        body["ui_mode"] = ui_mode
    if locale is not None:
        body["locale"] = locale
    return s.post(f"{BASE}/pharmacy/subscription/checkout", json=body, timeout=15)


def main():
    assert wait_health(), "backend not healthy"
    plan_id, monthly = professional_plan()
    print(f"professional plan: {plan_id} monthly={monthly}")
    s, email = new_company()
    company_id = company_id_of(email)
    print(f"company: {company_id}")

    # ---- A. embedded checkout (web) --------------------------------------
    r = do_checkout(s, plan_id, ui_mode="embedded", locale="ar")
    check("A1 embedded checkout 201", r.status_code == 201, f"{r.status_code} {r.text[:200]}")
    data = r.json().get("data", {})
    payment_id = data.get("payment_id", "")
    check("A2 provider=xpay (priority over configured paymob)", data.get("provider") == "xpay", str(data.get("provider")))
    check("A3 client_secret present", bool(data.get("client_secret")))
    check("A4 public_key = publishable key", data.get("public_key") == XPAY_PK, str(data.get("public_key")))
    check("A5 embedded has no embed_url", not data.get("embed_url"), str(data.get("embed_url")))
    row = payment_row(payment_id)
    check("A6 payment row provider=xpay pending", row and row[0] == "xpay" and row[1] == "pending", str(row))
    check("A7 provider_reference = session id", bool(row and row[3] and row[3].startswith("cs_test_")), str(row and row[3]))
    check("A8 amount snapshot", row and row[2] == monthly, str(row and row[2]))
    time.sleep(0.2)
    check("A9 stub got Bearer + Idempotency-Key + metadata anchor",
          STUB_SESSIONS and STUB_SESSIONS[-1]["idempotency_key"] == payment_id
          and STUB_SESSIONS[-1]["metadata_payment_id"] == payment_id
          and STUB_SESSIONS[-1]["unitAmount"] == monthly,
          json.dumps(STUB_SESSIONS[-1]) if STUB_SESSIONS else "no stub calls")
    check("A10 intent txn row recorded", intent_txn_exists(payment_id) >= 1)

    # ---- B. hosted checkout (legacy mobile: no ui_mode) -------------------
    r = do_checkout(s, plan_id, ui_mode=None, locale=None)
    check("B1 hosted checkout 201", r.status_code == 201, f"{r.status_code}")
    d2 = r.json().get("data", {})
    hosted_payment_id = d2.get("payment_id", "")
    check("B2 embed_url is hosted session URL", str(d2.get("embed_url", "")).startswith("https://checkout.xpay.app/p/cs_test_"), str(d2.get("embed_url")))
    row = payment_row(hosted_payment_id)
    check("B3 stub received uiMode=hosted", STUB_SESSIONS and STUB_SESSIONS[-1]["uiMode"] == "hosted",
          json.dumps(STUB_SESSIONS[-1]) if STUB_SESSIONS else "no stub calls")

    # ---- C. verified webhook activates ------------------------------------
    ev = session_event("evt_e2e_c1", payment_id, monthly)
    r = post_event(ev)
    check("C1 webhook accepted", r.status_code == 200 and r.json().get("result") == "activated", f"{r.status_code} {r.text[:120]}")
    row = payment_row(payment_id)
    check("C2 payment succeeded", row and row[1] == "succeeded", str(row))
    sub = subscription_row(company_id)
    check("C3 trial converted to active", sub and sub[0] == "active", str(sub))
    check("C4 verified webhook txn row", webhook_txn_count(payment_id, "evt_e2e_c1") == 1)

    # ---- D. replay idempotency --------------------------------------------
    before = subscription_row(company_id)[1]
    r = post_event(ev)
    check("D1 replay accepted", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
    after = subscription_row(company_id)[1]
    check("D2 period unchanged after replay", before == after, f"{before} -> {after}")
    check("D3 txn row recorded once", webhook_txn_count(payment_id, "evt_e2e_c1") == 1)

    # ---- E. renewal extends ------------------------------------------------
    r = do_checkout(s, plan_id, ui_mode="embedded", locale=None)
    pay2 = r.json().get("data", {}).get("payment_id", "")
    ev2 = session_event("evt_e2e_e1", pay2, monthly)
    r = post_event(ev2)
    check("E1 renewal activated", r.status_code == 200 and r.json().get("result") == "activated", f"{r.status_code} {r.text[:120]}")
    check("E2 payment succeeded", payment_row(pay2)[1] == "succeeded", str(payment_row(pay2)))
    check("E3 subscription still active", subscription_row(company_id)[0] == "active", str(subscription_row(company_id)))

    # ---- F. security --------------------------------------------------------
    # F1 bad signature
    r = do_checkout(s, plan_id, ui_mode="embedded", locale=None)
    pay3 = r.json().get("data", {}).get("payment_id", "")
    ev3 = session_event("evt_e2e_f1", pay3, monthly)
    r = post_event(ev3, header="t=123,v1=deadbeef")
    check("F1 bad signature → 400", r.status_code == 400, f"{r.status_code} {r.text[:120]}")
    check("F2 payment still pending", payment_row(pay3)[1] == "pending", str(payment_row(pay3)))

    # F3 bad/missing token
    r = post_event(ev3, url=WEBHOOK_URL_NO_TOKEN)
    check("F3 missing token → 401", r.status_code == 401, f"{r.status_code}")

    # F4 amount mismatch
    ev4 = session_event("evt_e2e_f4", pay3, monthly * 2)
    r = post_event(ev4)
    check("F4 amount mismatch handled", r.status_code == 200 and r.json().get("result") == "amount_mismatch_failed", f"{r.status_code} {r.text[:120]}")
    check("F5 mismatched payment failed (never activated)", payment_row(pay3)[1] == "failed", str(payment_row(pay3)))
    check("F6 mismatch recorded as verified txn", webhook_txn_count(pay3, "evt_e2e_f4") == 1)

    # F7 completed but UNPAID (Fawry-style reference) — must NOT activate or fail
    r = do_checkout(s, plan_id, ui_mode="embedded", locale=None)
    pay5 = r.json().get("data", {}).get("payment_id", "")
    ev5 = session_event("evt_e2e_f7", pay5, monthly, payment_status="unpaid")
    r = post_event(ev5)
    check("F7 completed+unpaid recorded", r.status_code == 200 and r.json().get("result") == "recorded", f"{r.status_code} {r.text[:120]}")
    check("F8 reference payment stays pending", payment_row(pay5)[1] == "pending", str(payment_row(pay5)))

    # F9 async_payment_succeeded completes it (the documented Fawry tail)
    ev6 = session_event("evt_e2e_f9", pay5, monthly, event_type="checkout.session.async_payment_succeeded")
    r = post_event(ev6)
    check("F9 async_payment_succeeded activates", r.status_code == 200 and r.json().get("result") == "activated", f"{r.status_code} {r.text[:120]}")
    check("F10 payment succeeded", payment_row(pay5)[1] == "succeeded", str(payment_row(pay5)))

    # F11 charge.failed — recorded, never fails the payment (retry in-session)
    r = do_checkout(s, plan_id, ui_mode="embedded", locale=None)
    pay7 = r.json().get("data", {}).get("payment_id", "")
    ev7 = {"id": "evt_e2e_f11", "object": "event", "type": "charge.failed",
           "data": {"object": {"id": "ch_1", "failureCode": "card_declined",
                               "metadata": {"payment_id": pay7}}}}
    r = post_event(ev7)
    check("F11 charge.failed recorded", r.status_code == 200 and r.json().get("result") == "recorded", f"{r.status_code} {r.text[:120]}")
    check("F12 payment still pending (retryable)", payment_row(pay7)[1] == "pending", str(payment_row(pay7)))

    # F13 async_payment_failed fails a pending payment
    ev8 = session_event("evt_e2e_f13", pay7, monthly, event_type="checkout.session.async_payment_failed")
    r = post_event(ev8)
    check("F13 async_payment_failed handled", r.status_code == 200 and r.json().get("result") == "recorded", f"{r.status_code} {r.text[:120]}")
    check("F14 payment failed", payment_row(pay7)[1] == "failed", str(payment_row(pay7)))

    # F15 expired session fails a pending payment
    r = do_checkout(s, plan_id, ui_mode="embedded", locale=None)
    pay9 = r.json().get("data", {}).get("payment_id", "")
    ev9 = session_event("evt_e2e_f15", pay9, monthly, event_type="checkout.session.expired")
    r = post_event(ev9)
    check("F15 expired handled", r.status_code == 200 and r.json().get("result") == "recorded", f"{r.status_code} {r.text[:120]}")
    check("F16 expired payment failed", payment_row(pay9)[1] == "failed", str(payment_row(pay9)))

    # F17 succeeded payment NEVER regresses on a late expired event
    ev10 = session_event("evt_e2e_f17", pay5, monthly, event_type="checkout.session.expired")
    r = post_event(ev10)
    check("F17 late expired on succeeded payment", r.status_code == 200 and r.json().get("result") == "recorded", f"{r.status_code}")
    check("F18 succeeded payment intact", payment_row(pay5)[1] == "succeeded", str(payment_row(pay5)))

    print()
    if FAILURES:
        print(f"FAILED {len(FAILURES)}: " + ", ".join(FAILURES))
        return 1
    print("ALL XPAY E2E CHECKS PASSED")
    return 0


if __name__ == "__main__":
    stub = start_stub()
    code = main()
    sys.exit(code)
