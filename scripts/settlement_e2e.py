#!/usr/bin/env python3
"""E2E — Payment Settlement & Reconciliation (Phase S1, migration 32).

Run against a server on :8080 booted with the platform super-admin bootstrap
env + BOTH gateways configured, XPAY_BASE_URL pointing at the local stub
gateway this script spins up on 127.0.0.1:9555 (now also serving
GET /checkout/sessions/:id for the resync pull path).

Covers:
  G. webhook activation → confirmed_at + confirmation_source='webhook' +
     settlement row 'pending' (captured, payout not yet matched)
  H. settlement action: note required; payout reference required for
     settled; success writes settlement txn + audit; manual payments refuse
  I. lost-webhook recovery: stale pending (>24h) shows in reconciliation,
     resync pulls the session (paid) → activates with source='sync',
     duplicate resync stays idempotent (period never double-extends)
  J. resync amount mismatch → conflict_flagged, needs_review, settlement
     unknown — never activated
  K. resync expired session → failed_marked
  L. resync on a succeeded+paid payment → consistent
  M. resync on a succeeded payment the provider no longer reports paid →
     conflict_flagged, the succeeded row NEVER regresses
  N. reconciliation buckets + summary counts
  O. charge.refunded webhook: partial keeps succeeded, full flips refunded
  P. ledger: new fields (number, settlement_status, needs_review) + filters
  Q. resync on a paymob payment → 400 (xpay-only pull today)
  R. unanchored charge.* events → 200 ignored (no retry storm)
  S. human references SUB-/PAY- assigned
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
PLATFORM = ("e2e-admin@pharmacyos.test", "E2eAdmin#2026")
XPAY_SECRET = "sk_test_e2e"
WEBHOOK_SECRET = "whsec_e2e_secret"
WEBHOOK_TOKEN = "xpay_e2e_token"
WEBHOOK_URL = f"{BASE}/payments/webhook/xpay?token={WEBHOOK_TOKEN}"
STUB_PORT = 9555
FAILURES = []

# session_id -> {"status": open|complete|expired, "paymentStatus": paid|unpaid,
#                "amountTotal": int} — tests mutate to simulate provider truth.
STUB_STATE = {}
STUB_SESSIONS = []


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
        if self.headers.get("Authorization", "") != f"Bearer {XPAY_SECRET}":
            return self._json(401, {"error": "unauthorized"})
        req = json.loads(raw)
        payment_id = (req.get("metadata") or {}).get("payment_id", "")
        sid = "cs_test_" + uuid.uuid4().hex[:16]
        STUB_STATE[sid] = {"status": "open", "paymentStatus": "unpaid",
                           "amountTotal": int(req["lineItems"][0]["priceData"]["unitAmount"]),
                           "currency": req["lineItems"][0]["priceData"]["currency"]}
        STUB_SESSIONS.append({"idempotency_key": self.headers.get("Idempotency-Key", ""),
                              "metadata_payment_id": payment_id, "session_id": sid})
        return self._json(201, {"id": sid, "object": "checkout.session", "status": "open",
                                "paymentStatus": "unpaid", "amountTotal": STUB_STATE[sid]["amountTotal"],
                                "currency": STUB_STATE[sid]["currency"],
                                "clientSecret": "cs_secret_" + sid,
                                "metadata": {"payment_id": payment_id}})

    def do_GET(self):
        if not self.path.startswith("/checkout/sessions/"):
            return self._json(404, {"error": "not_found"})
        if self.headers.get("Authorization", "") != f"Bearer {XPAY_SECRET}":
            return self._json(401, {"error": "unauthorized"})
        sid = self.path.rsplit("/", 1)[-1].split("?")[0]
        st = STUB_STATE.get(sid)
        if st is None:
            return self._json(404, {"error": "session_not_found"})
        return self._json(200, {"id": sid, "object": "checkout.session",
                                "status": st.get("status", "open"), "paymentStatus": st.get("paymentStatus", "unpaid"),
                                "amountTotal": st.get("amountTotal", 0), "currency": st.get("currency", "EGP"),
                                "metadata": {"payment_id": st.get("payment_id", "")}})


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


def sql(query, args=()):
    conn = db()
    cur = conn.cursor()
    cur.execute(query, args)
    rows = cur.fetchall() if cur.description else []
    conn.close()
    return rows


def new_company():
    email = f"settle-e2e-{uuid.uuid4().hex[:8]}@test.io"
    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": "صيدلية التسوية", "company_email": email,
        "first_name": "المالك", "last_name": "التسوية",
        "email": email, "password": PASSWORD,
    }, timeout=10)
    assert r.status_code in (200, 201), r.text
    sql("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (email,))
    sql("UPDATE pharmacies SET settings = settings || '{\"onboarding\": {\"completed\": true}}'::jsonb "
        "WHERE account_id IN (SELECT id FROM accounts WHERE contact_email=%s)", (email,))
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": PASSWORD}, timeout=10)
    assert r.status_code == 200, r.text
    s.headers["X-CSRF-Token"] = s.cookies.get("pharmacy_csrf", "")
    return s, email


def platform_session():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/platform/login",
               json={"email": PLATFORM[0], "password": PLATFORM[1]}, timeout=10)
    assert r.status_code == 200, r.text
    s.headers["X-CSRF-Token"] = s.cookies.get("platform_csrf", "")
    return s


def professional_plan():
    row = sql("SELECT id::text, monthly_price_piastres FROM plans WHERE slug='professional' LIMIT 1")
    return row[0][0], int(row[0][1])


def payment_row(payment_id):
    rows = sql("""SELECT provider, status, amount_piastres, provider_reference,
                         to_char(confirmed_at, 'YYYY-MM-DD HH24:MI'), COALESCE(confirmation_source,''),
                         refunded_amount_piastres, needs_review, number
                  FROM payments WHERE id=%s""", (payment_id,))
    return rows[0] if rows else None


def settlement_row(payment_id):
    rows = sql("SELECT status, provider_settlement_reference, settled_at IS NOT NULL, last_synced_at IS NOT NULL"
               " FROM payment_settlements WHERE payment_id=%s", (payment_id,))
    return rows[0] if rows else None


def subscription_row(company_id):
    rows = sql("SELECT status, current_period_end::text, reference FROM subscriptions"
               " WHERE company_id=%s ORDER BY created_at DESC LIMIT 1", (company_id,))
    return rows[0] if rows else None


def txn_count(payment_id, txn_type, ref=None):
    if ref is None:
        rows = sql("SELECT COUNT(*) FROM payment_transactions WHERE payment_id=%s AND txn_type=%s",
                   (payment_id, txn_type))
    else:
        rows = sql("SELECT COUNT(*) FROM payment_transactions WHERE payment_id=%s AND txn_type=%s"
                   " AND provider_transaction_id=%s", (payment_id, txn_type, ref))
    return int(rows[0][0])


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
                  payment_status="paid", session_id=None, extra_obj=None):
    obj = {"id": session_id or ("cs_test_" + uuid.uuid4().hex[:16]),
           "object": "checkout.session",
           "status": "complete" if event_type == "checkout.session.completed" else "open",
           "paymentStatus": payment_status, "amountTotal": amount, "currency": "EGP",
           "metadata": {"payment_id": payment_id}}
    if extra_obj:
        obj.update(extra_obj)
    return {"id": event_id, "object": "event", "type": event_type, "data": {"object": obj}}


def do_checkout(s, plan_id, ui_mode="embedded", locale="ar"):
    return s.post(f"{BASE}/pharmacy/subscription/checkout",
                  json={"plan_id": plan_id, "billing_interval": "monthly",
                        "ui_mode": ui_mode, "locale": locale}, timeout=15)


def resync(plat, payment_id):
    return plat.post(f"{BASE}/platform-admin/payments/{payment_id}/resync", json={}, timeout=20)


def settle(plat, payment_id, body):
    return plat.post(f"{BASE}/platform-admin/payments/{payment_id}/settlement", json=body, timeout=15)


def age_payment(payment_id, hours=25):
    sql(f"UPDATE payments SET created_at = NOW() - INTERVAL '{int(hours)} hours' WHERE id=%s", (payment_id,))


def main():
    assert wait_health(), "backend not healthy"
    plan_id, monthly = professional_plan()
    plat = platform_session()
    print(f"professional plan: {plan_id} monthly={monthly}")

    # ---- G. webhook activation: confirmation stamp + settlement pending ---
    s, email = new_company()
    company_id = sql("SELECT company_id::text FROM company_users WHERE email=%s", (email,))[0][0]
    r = do_checkout(s, plan_id)
    assert r.status_code == 201, r.text
    pay_g = r.json()["data"]["payment_id"]
    stub_sid = STUB_SESSIONS[-1]["session_id"]
    r = post_event(session_event("evt_s_g1", pay_g, monthly, session_id=stub_sid))
    check("G1 webhook activated", r.status_code == 200 and r.json().get("result") == "activated",
          f"{r.status_code} {r.text[:150]}")
    row = payment_row(pay_g)
    check("G2 payment succeeded", row and row[1] == "succeeded", str(row))
    check("G3 confirmed_at stamped", bool(row and row[4]), str(row))
    check("G4 confirmation_source=webhook", row and row[5] == "webhook", str(row))
    srow = settlement_row(pay_g)
    check("G5 settlement row pending", srow and srow[0] == "pending", str(srow))
    check("G6 settlement last_synced set", srow and srow[3], str(srow))
    check("G7 PAY- number assigned", bool(row and row[8] and row[8].startswith("PAY-")), str(row and row[8]))
    sub = subscription_row(company_id)
    check("G8 SUB- reference assigned", bool(sub and sub[2] and sub[2].startswith("SUB-")), str(sub))

    # ---- H. settlement action ----------------------------------------------
    r = settle(plat, pay_g, {"status": "settled", "note": ""})
    check("H1 note required", r.status_code == 400 and r.json().get("error") == "note_required",
          f"{r.status_code} {r.text[:120]}")
    r = settle(plat, pay_g, {"status": "settled", "note": "بدون مرجع"})
    check("H2 payout reference required for settled",
          r.status_code == 400 and r.json().get("error") == "reference_required",
          f"{r.status_code} {r.text[:120]}")
    r = settle(plat, pay_g, {"status": "settled", "note": "دفعة تحويل XP-2026-09",
                             "provider_settlement_reference": "po_batch_88",
                             "fees_piastres": 1250})
    check("H3 settled accepted", r.status_code == 200 and r.json()["data"]["settlement_status"] == "settled",
          f"{r.status_code} {r.text[:150]}")
    srow = settlement_row(pay_g)
    check("H4 settlement settled + reference", srow and srow[0] == "settled" and srow[1] == "po_batch_88" and srow[2],
          str(srow))
    check("H5 settlement txn recorded", txn_count(pay_g, "settlement") == 1)
    audit = sql("SELECT COUNT(*) FROM platform_audit_logs WHERE action='payment.settlement' AND entity_id=%s",
                (pay_g,))[0][0]
    check("H6 settlement audited", int(audit) >= 1, str(audit))
    # manual payments have no settlement
    r = plat.post(f"{BASE}/platform-admin/payments/manual", json={
        "company_id": company_id, "plan_id": plan_id, "billing_interval": "monthly",
        "note": "دفع يدوي e2e", "idempotency_key": "settle-e2e-" + uuid.uuid4().hex[:8]}, timeout=15)
    check("H7 manual payment 201", r.status_code == 201, f"{r.status_code} {r.text[:120]}")
    manual_pay = r.json()["data"]["payment_id"]
    mrow = payment_row(manual_pay)
    check("H8 manual confirmed_at + source=manual", bool(mrow and mrow[4]) and mrow[5] == "manual", str(mrow))
    r = settle(plat, manual_pay, {"status": "settled", "note": "محاولة على دفعة يدوية",
                                  "provider_settlement_reference": "po_manual"})
    check("H9 manual payment refuses settlement", r.status_code == 409, f"{r.status_code} {r.text[:120]}")

    # ---- I. lost-webhook recovery via resync --------------------------------
    s2, email2 = new_company()
    r = do_checkout(s2, plan_id)
    assert r.status_code == 201, r.text
    pay_i = r.json()["data"]["payment_id"]
    sid_i = STUB_SESSIONS[-1]["session_id"]
    company2 = sql("SELECT company_id::text FROM company_users WHERE email=%s", (email2,))[0][0]
    age_payment(pay_i)
    r = plat.get(f"{BASE}/platform-admin/payments/reconciliation", timeout=15)
    stale_ids = [x["id"] for x in r.json()["data"]["stale_pending"]]
    check("I1 stale pending listed in reconciliation", pay_i in stale_ids, f"{r.status_code}")
    STUB_STATE[sid_i] = {"status": "complete", "paymentStatus": "paid",
                         "amountTotal": monthly, "payment_id": pay_i}
    r = resync(plat, pay_i)
    check("I2 resync activated", r.status_code == 200 and r.json()["data"]["result"] == "activated",
          f"{r.status_code} {r.text[:150]}")
    row = payment_row(pay_i)
    check("I3 confirmation_source=sync", row and row[5] == "sync", str(row))
    check("I4 payment succeeded", row and row[1] == "succeeded", str(row))
    check("I5 settlement row created", settlement_row(pay_i) is not None, str(settlement_row(pay_i)))
    check("I6 sync txn recorded", txn_count(pay_i, "sync") == 1)
    period1 = subscription_row(company2)[1]
    r = resync(plat, pay_i)
    check("I7 duplicate resync → consistent", r.status_code == 200 and r.json()["data"]["result"] == "consistent",
          f"{r.status_code} {r.text[:150]}")
    check("I8 period unchanged (no double-extend)", subscription_row(company2)[1] == period1,
          f"{period1} -> {subscription_row(company2)[1]}")

    # ---- J. resync amount mismatch → conflict, never activated --------------
    s3, _ = new_company()
    r = do_checkout(s3, plan_id)
    pay_j = r.json()["data"]["payment_id"]
    sid_j = STUB_SESSIONS[-1]["session_id"]
    age_payment(pay_j)
    STUB_STATE[sid_j] = {"status": "complete", "paymentStatus": "paid",
                         "amountTotal": monthly - 500, "payment_id": pay_j}
    r = resync(plat, pay_j)
    check("J1 mismatch resync → conflict_flagged", r.status_code == 200 and r.json()["data"]["result"] == "conflict_flagged",
          f"{r.status_code} {r.text[:150]}")
    row = payment_row(pay_j)
    check("J2 payment still pending (never activated on mismatch)", row and row[1] == "pending", str(row))
    check("J3 needs_review raised", row and row[7], str(row))
    srow = settlement_row(pay_j)
    check("J4 settlement unknown", srow and srow[0] == "unknown", str(srow))
    # resolving: settled path requires succeeded — remains blocked; review clears only via admin decision
    r = settle(plat, pay_j, {"status": "disputed", "note": "اختلاف مبلغ — مراجعة يدوية"})
    check("J5 disputed recorded on non-succeeded blocked", r.status_code == 409, f"{r.status_code}")

    # ---- K. resync expired session → failed_marked ---------------------------
    s4, _ = new_company()
    r = do_checkout(s4, plan_id)
    pay_k = r.json()["data"]["payment_id"]
    sid_k = STUB_SESSIONS[-1]["session_id"]
    STUB_STATE[sid_k] = {"status": "expired", "paymentStatus": "unpaid", "amountTotal": monthly, "payment_id": pay_k}
    r = resync(plat, pay_k)
    check("K1 expired resync → failed_marked", r.status_code == 200 and r.json()["data"]["result"] == "failed_marked",
          f"{r.status_code} {r.text[:150]}")
    row = payment_row(pay_k)
    check("K2 payment failed", row and row[1] == "failed", str(row))

    # ---- L+M. succeeded payment: consistent vs conflict ----------------------
    s5, email5 = new_company()
    company5 = sql("SELECT company_id::text FROM company_users WHERE email=%s", (email5,))[0][0]
    r = do_checkout(s5, plan_id)
    pay_l = r.json()["data"]["payment_id"]
    sid_l = STUB_SESSIONS[-1]["session_id"]
    STUB_STATE[sid_l] = {"status": "complete", "paymentStatus": "paid",
                         "amountTotal": monthly, "payment_id": pay_l}  # provider truth for resync L1
    post_event(session_event("evt_s_l1", pay_l, monthly, session_id=sid_l))
    assert payment_row(pay_l)[1] == "succeeded"
    r = resync(plat, pay_l)
    check("L1 succeeded+paid resync → consistent", r.status_code == 200 and r.json()["data"]["result"] == "consistent",
          f"{r.status_code} {r.text[:150]}")
    row = payment_row(pay_l)
    check("L2 status never regressed", row and row[1] == "succeeded", str(row))
    check("L3 confirmation stays webhook (first wins)", row and row[5] == "webhook", str(row))
    # provider stops reporting paid (edge: dispute/rollback on their side)
    STUB_STATE[sid_l] = {"status": "complete", "paymentStatus": "unpaid", "amountTotal": monthly, "payment_id": pay_l}
    r = resync(plat, pay_l)
    check("M1 succeeded+unpaid resync → conflict_flagged", r.status_code == 200 and r.json()["data"]["result"] == "conflict_flagged",
          f"{r.status_code} {r.text[:150]}")
    row = payment_row(pay_l)
    check("M2 succeeded NEVER regresses", row and row[1] == "succeeded", str(row))
    check("M3 needs_review raised", row and row[7], str(row))
    sub5_before = subscription_row(company5)[1]
    check("M4 subscription untouched", sub5_before is not None, str(sub5_before))

    # ---- N. reconciliation buckets ------------------------------------------
    r = plat.get(f"{BASE}/platform-admin/payments/reconciliation", timeout=15)
    d = r.json()["data"]
    check("N1 reconciliation 200", r.status_code == 200, f"{r.status_code}")
    check("N2 needs_review bucket contains M-flagged", pay_l in [x["id"] for x in d["needs_review"]],
          str(len(d["needs_review"])))
    check("N3 settled payment NOT in confirmed_unsettled", pay_g not in [x["id"] for x in d["confirmed_unsettled"]],
          str(len(d["confirmed_unsettled"])))
    check("N4 pay_l in confirmed_unsettled (settlement unknown ≠ settled)",
          pay_l in [x["id"] for x in d["confirmed_unsettled"]], str(len(d["confirmed_unsettled"])))
    check("N5 stale_pending empty now (all resolved)", pay_i not in [x["id"] for x in d["stale_pending"]],
          str(len(d["stale_pending"])))
    check("N6 summary counts present", all(k in d["summary"] for k in
          ("stale_pending_count", "confirmed_unsettled_count", "needs_review_count",
           "settlement_conflicts_count", "refunded_count")), json.dumps(d["summary"]))

    # ---- O. charge.refunded webhook ------------------------------------------
    r = post_event(session_event("evt_s_o1", pay_l, monthly, event_type="charge.refunded",
                                 payment_status="paid", session_id=sid_l,
                                 extra_obj={"amountRefunded": monthly // 2}))
    check("O1 partial refund accepted", r.status_code == 200 and r.json().get("result") == "refund_recorded",
          f"{r.status_code} {r.text[:120]}")
    row = payment_row(pay_l)
    check("O2 partial refund keeps succeeded", row and row[1] == "succeeded", str(row))
    check("O3 refunded_amount updated", row and row[6] == monthly // 2, str(row))
    r = post_event(session_event("evt_s_o2", pay_l, monthly, event_type="charge.refunded",
                                 payment_status="paid", session_id=sid_l,
                                 extra_obj={"amountRefunded": monthly}))
    row = payment_row(pay_l)
    check("O4 full refund flips status", row and row[1] == "refunded", str(row))
    check("O5 refunded bucket lists it",
          pay_l in [x["id"] for x in plat.get(f"{BASE}/platform-admin/payments/reconciliation",
                                              timeout=15).json()["data"]["refunded"]])

    # ---- P. ledger fields + filters -------------------------------------------
    r = plat.get(f"{BASE}/platform-admin/payments?needs_review=true", timeout=15)
    ids = [x["id"] for x in r.json()["data"]]
    check("P1 needs_review filter works", pay_l in ids, f"{len(ids)} rows")
    r = plat.get(f"{BASE}/platform-admin/payments?settlement=settled", timeout=15)
    ids = [x["id"] for x in r.json()["data"]]
    check("P2 settlement=settled filter works", pay_g in ids, f"{len(ids)} rows")
    r = plat.get(f"{BASE}/platform-admin/payments?settlement=unsettled", timeout=15)
    ids = [x["id"] for x in r.json()["data"]]
    check("P3 settlement=unsettled filter works", pay_l in ids and pay_g not in ids, f"{len(ids)} rows")
    r = plat.get(f"{BASE}/platform-admin/payments", timeout=15)
    first = r.json()["data"][0]
    check("P4 ledger exposes number + settlement_status + confirmation_source",
          "number" in first and "settlement_status" in first and "confirmation_source" in first
          and "confirmed_at" in first and "refunded_amount_piastres" in first, json.dumps(list(first.keys())))

    # ---- Q. resync on paymob payment → 400 -----------------------------------
    sql("""INSERT INTO payments (company_id, plan_id, billing_interval, amount_piastres,
               currency, provider, status, provider_reference, confirmed_at, confirmation_source)
           VALUES (%s, %s, 'monthly', %s, 'EGP', 'paymob', 'succeeded', 'pm-int-e2e', NOW(), 'webhook')""",
        (company5, plan_id, monthly))
    pm_pay = sql("SELECT id::text FROM payments WHERE provider='paymob' AND provider_reference='pm-int-e2e'")[0][0]
    r = resync(plat, pm_pay)
    check("Q1 paymob resync rejected 400", r.status_code == 400
          and r.json().get("error") == "resync_not_supported_provider", f"{r.status_code} {r.text[:120]}")

    # ---- Q2. detail endpoint: row + settlement + event timeline ---------------
    r = plat.get(f"{BASE}/platform-admin/payments/{pay_g}", timeout=15)
    d = r.json().get("data", {})
    tl_types = [x["txn_type"] for x in d.get("timeline", [])]
    check("Q2 detail 200 with timeline", r.status_code == 200 and len(d.get("timeline", [])) >= 3,
          f"{r.status_code} {r.text[:150]}")
    check("Q3 timeline has intent+webhook+settlement",
          all(x in tl_types for x in ("intent", "webhook", "settlement")), str(tl_types))
    check("Q4 detail settlement snapshot settled", d.get("settlement", {}).get("status") == "settled",
          str(d.get("settlement")))
    check("Q5 detail confirmation fields", d.get("confirmation_source") == "webhook"
          and bool(d.get("confirmed_at")), str(d.get("confirmation_source")))
    r = plat.get(f"{BASE}/platform-admin/payments/{pm_pay}", timeout=15)
    check("Q6 paymob detail settlement manual/missing", r.status_code == 200
          and r.json()["data"]["settlement"]["status"] in ("manual", "missing"), r.text[:120])

    # ---- R. unanchored charge.* events are ignored, not 400 -------------------
    r = post_event(session_event("evt_s_r1", "no-such-payment", monthly, event_type="charge.succeeded",
                                 payment_status="paid", session_id="cs_test_orphan_" + uuid.uuid4().hex[:6]))
    check("R1 unanchored charge.succeeded → 200 ignored", r.status_code == 200
          and r.json().get("result") == "ignored_unanchored", f"{r.status_code} {r.text[:120]}")
    r = post_event(session_event("evt_s_r2", "no-such-payment", monthly,
                                 event_type="checkout.session.completed", session_id="cs_test_orphan2_" + uuid.uuid4().hex[:6]))
    check("R2 unanchored checkout.session.* → 400 (must retry)",
          r.status_code == 400, f"{r.status_code}")

    # ---- S. references ---------------------------------------------------------
    refs = sql("SELECT reference FROM subscriptions WHERE reference IS NOT NULL LIMIT 3")
    check("S1 subscription references SUB-xxxxx", all(r[0].startswith("SUB-") and len(r[0]) == 9 for r in refs),
          str(refs))
    nums = sql("SELECT number FROM payments WHERE number IS NOT NULL LIMIT 3")
    check("S2 payment numbers PAY-xxxxx", all(n[0].startswith("PAY-") and len(n[0]) == 9 for n in nums),
          str(nums))

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print("  - " + f)
        sys.exit(1)
    print("ALL SETTLEMENT E2E CHECKS PASSED")


if __name__ == "__main__":
    start_stub()
    main()
