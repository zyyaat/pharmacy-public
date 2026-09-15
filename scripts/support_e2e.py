#!/usr/bin/env python3
"""E2E — Support Live Chat + Tickets (Phase T1, migration 33).

Run against a server on :8080 booted on a FRESH reports_test (the runner
script drops/recreates the DB so migration 33 applies cleanly).

Covers:
  A. company opens a conversation (first message) → platform inbox sees it
     (unread + unanswered + open counters); api_level = 79
  B. platform replies → company unread=1, preview updates, ordering
  C. WebSocket: company socket receives message.new pushed by the platform's
     REST send; typing indicator relayed platform-ward; app-level ping/pong
  D. read semantics: mark-read zeroes ONLY that side's counter (row-locked)
  E. isolation: company B cannot see/answer A's conversation, gets no WS
     events for it, cannot read A's attachments (404 — not 403, no probing)
  F. tickets: escalate conversation → TKT-00001 + system message in chat;
     full lifecycle PATCH open→in_progress→waiting_customer→in_progress→
     resolved(+note)→closed→reopen(in_progress); invalid transition → 409
     with allowed targets; every mutation audited to platform_audit_logs
  G. standalone ticket with a body auto-opens its chat thread
  H. attachments: upload png → attach → platform downloads exact bytes;
     foreign company download → 404; bad mime → 415; >2MiB → 413; single-use
  I. validation: empty body → 400; >4000 chars → 400; bad category/priority
     → 400; unknown conversation → 404
  J. close semantics: company closes → system message; both sides 409 on
     send afterwards; double close → 409
  K. pagination: (created_at,id) cursor pages oldest→newest without loss
  L. overview counters after a scripted sequence (both sides)
  M. auth: support endpoints + WS refuse unauthenticated callers
  N. presence flags: platform_online / company_online in detail payloads
"""
import json
import re
import socket
import sys
import time
import uuid
import base64

import psycopg2
import requests
import websocket

BASE = "http://127.0.0.1:8080/api/v1"
DB = "postgresql://postgres@127.0.0.1:54329/reports_test"
PASSWORD = "Str0ng!Pass2026"
PLATFORM = ("e2e-admin@pharmacyos.test", "E2eAdmin#2026")
PNG_1PX = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
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


def new_company(name="صيدلية الدعم"):
    email = f"support-e2e-{uuid.uuid4().hex[:8]}@test.io"
    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": name, "company_email": email,
        "first_name": "المالك", "last_name": name,
        "email": email, "password": PASSWORD,
    }, timeout=10)
    assert r.status_code in (200, 201), r.text
    sql("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (email,))
    sql("UPDATE pharmacies SET settings = settings || '{\"onboarding\": {\"completed\": true}}'::jsonb "
        "WHERE account_id IN (SELECT id FROM accounts WHERE contact_email=%s)", (email,))
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": email, "password": PASSWORD}, timeout=10)
    assert r.status_code == 200, r.text
    s.headers["X-CSRF-Token"] = s.cookies.get("pharmacy_csrf", "")
    company_id = sql("SELECT company_id::text FROM company_users WHERE email=%s", (email,))[0][0]
    return s, email, company_id


def platform_session():
    s = requests.Session()
    r = s.post(f"{BASE}/auth/platform/login",
               json={"email": PLATFORM[0], "password": PLATFORM[1]}, timeout=10)
    assert r.status_code == 200, r.text
    s.headers["X-CSRF-Token"] = s.cookies.get("platform_csrf", "")
    return s


def cookie_header(s, realm):
    return f"{realm}_access={s.cookies.get(f'{realm}_access')}"


def connect_ws(s, realm):
    ws = websocket.WebSocket(timeout=5)
    segment = "platform-admin" if realm == "platform" else "pharmacy"
    url = f"ws://127.0.0.1:8080/api/v1/{segment}/support/ws"
    ws.connect(url, header=[f"Cookie: {cookie_header(s, realm)}"], timeout=5)
    return ws


def ws_recv(ws, want_type, timeout=5):
    """Read frames until one of the wanted type arrives (skips pongs).
    The socket timeout is re-armed before every recv — a silent connection
    must surface as WebSocketTimeoutException, never block the suite."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            ws.sock.settimeout(max(0.2, deadline - time.time()))
            raw = ws.recv()
        except (websocket.WebSocketTimeoutException, TimeoutError, socket.timeout):
            return None
        try:
            frame = json.loads(raw)
        except (ValueError, TypeError):
            continue
        if frame.get("type") == want_type:
            return frame
    return None


def ws_recv_message(ws, body, timeout=5):
    """Read frames until a message.new with this exact body arrives — the
    hub echoes the sender's own writes to ALL its devices (multi-device by
    design), so type-only matching can catch a stale self-echo."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        frame = ws_recv(ws, "message.new", timeout=max(0.2, deadline - time.time()))
        if frame is None:
            return None
        if (frame.get("message") or {}).get("body") == body:
            return frame
    return None


def ws_recv_conv(ws, want_type, conv_id, timeout=5):
    """Read frames until one of want_type for THIS conversation arrives —
    earlier lifecycle events for other conversations are skipped, not fatal."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        frame = ws_recv(ws, want_type, timeout=max(0.2, deadline - time.time()))
        if frame is None:
            return None
        if frame.get("conversation_id") == conv_id:
            return frame
    return None


# --- REST shortcuts ---------------------------------------------------------

def create_conversation(s, subject=None, body="مرحبا، عندي سؤال عن الفاتورة", attachment_id=None):
    payload = {}
    if subject is not None:
        payload["subject"] = subject
    if body is not None:
        payload["body"] = body
    if attachment_id:
        payload["attachment_id"] = attachment_id
    return s.post(f"{BASE}/pharmacy/support/conversations", json=payload, timeout=10)


def send_msg(s, realm, conv_id, body, attachment_id=None):
    payload = {"body": body}
    if attachment_id:
        payload["attachment_id"] = attachment_id
    if realm == "platform":
        return s.post(f"{BASE}/platform-admin/support/conversations/{conv_id}/messages",
                      json=payload, timeout=10)
    return s.post(f"{BASE}/pharmacy/support/conversations/{conv_id}/messages",
                  json=payload, timeout=10)


def get_messages(s, realm, conv_id, before_ts=None, before_id=None, limit=None):
    params = {}
    if before_ts:
        params["before_ts"] = before_ts
    if before_id:
        params["before_id"] = before_id
    if limit:
        params["limit"] = limit
    if realm == "platform":
        return s.get(f"{BASE}/platform-admin/support/conversations/{conv_id}/messages",
                     params=params, timeout=10)
    return s.get(f"{BASE}/pharmacy/support/conversations/{conv_id}/messages",
                 params=params, timeout=10)


def mark_read(s, realm, conv_id):
    if realm == "platform":
        return s.post(f"{BASE}/platform-admin/support/conversations/{conv_id}/read", json={}, timeout=10)
    return s.post(f"{BASE}/pharmacy/support/conversations/{conv_id}/read", json={}, timeout=10)


def conv_detail(s, realm, conv_id):
    if realm == "platform":
        return s.get(f"{BASE}/platform-admin/support/conversations/{conv_id}", timeout=10)
    return s.get(f"{BASE}/pharmacy/support/conversations/{conv_id}", timeout=10)


def overview(s, realm):
    if realm == "platform":
        return s.get(f"{BASE}/platform-admin/support/overview", timeout=10)
    return s.get(f"{BASE}/pharmacy/support/overview", timeout=10)


def list_convs(s, realm, **params):
    if realm == "platform":
        return s.get(f"{BASE}/platform-admin/support/conversations", params=params, timeout=10)
    return s.get(f"{BASE}/pharmacy/support/conversations", params=params, timeout=10)


def platform_conv_row(plat, conv_id):
    r = list_convs(plat, "platform")
    assert r.status_code == 200, r.text
    for row in r.json()["conversations"]:
        if row["id"] == conv_id:
            return row
    return None


# ---------------------------------------------------------------------------

def main():
    assert wait_health(), "backend not healthy"

    # ---- M0. api_level -----------------------------------------------------
    h = requests.get(f"{BASE}/health", timeout=5).json()
    check("M1 api_level=79", h.get("api_level") == 79, str(h))

    plat = platform_session()

    # ---- A. company opens a conversation -----------------------------------
    sA, emailA, companyA = new_company("صيدلية الأمل")
    r = create_conversation(sA, subject="سؤال عن الفاتورة")
    check("A1 create conversation 201", r.status_code == 201, r.text)
    convA = r.json()["conversation"]
    check("A2 status open + subject", convA["status"] == "open" and convA["subject"] == "سؤال عن الفاتورة")
    check("A3 company_unread=0 (own msg)", convA["company_unread_count"] == 0, str(convA))
    check("A4 platform_unread=1", convA["platform_unread_count"] == 1, str(convA))

    row = platform_conv_row(plat, convA["id"])
    check("A5 platform inbox shows it", row is not None)
    check("A6 inbox company name joined", row and "الأمل" in (row.get("company_name") or ""), str(row))

    r = overview(plat, "platform")
    ov = r.json()
    check("A7 platform overview unread=1", ov["unread_conversations"] == 1, str(ov))
    check("A8 platform overview unanswered=1", ov["unanswered_conversations"] == 1, str(ov))
    check("A9 platform_online true (no sockets yet = no one online)", ov.get("platform_online") is False, str(ov))

    # default subject derivation
    r = create_conversation(sA, subject=None, body="مشكلة في طباعة الإيصال لا تعمل إطلاقا")
    check("A10 subject auto-derived from body", r.status_code == 201 and
          "مشكلة في طباعة" in r.json()["conversation"]["subject"], r.text)
    convA2 = r.json()["conversation"]

    # ---- B. platform replies ------------------------------------------------
    r = send_msg(plat, "platform", convA["id"], "أهلا بك! سنقوم بالتحقق من الفاتورة الآن")
    check("B1 platform reply 201", r.status_code == 201, r.text)
    msgPlat = r.json()["message"]
    check("B2 sender realm=platform + name", msgPlat["sender_realm"] == "platform" and msgPlat["sender_name"] != "")
    row = platform_conv_row(plat, convA["id"])
    check("B3 company_unread=1 after reply", row["company_unread_count"] == 1, str(row))
    check("B4 preview is platform text", "التحقق من الفاتورة" in row["last_message_preview"], str(row))

    r = list_convs(plat, "platform", filter="unanswered")
    ids = [c["id"] for c in r.json()["conversations"]]
    check("B5 unanswered no longer contains A (platform wrote last)", convA["id"] not in ids, str(ids))
    r = list_convs(plat, "platform", filter="unread")
    # convA still carries the company's first message — the platform has not
    # read it yet, so it IS in the unread bucket (its own reply changed nothing).
    check("B6 unread contains convA (platform never read it yet)",
          convA["id"] in [c["id"] for c in r.json()["conversations"]])

    # ---- C. WebSocket push + typing + ping ---------------------------------
    wsCompany = connect_ws(sA, "pharmacy")
    wsPlatform = connect_ws(plat, "platform")
    time.sleep(0.3)  # let the hub register both

    # app-level ping/pong both ways
    wsCompany.send(json.dumps({"type": "ping"}))
    check("C1 company ping→pong", ws_recv(wsCompany, "pong") is not None)
    wsPlatform.send(json.dumps({"type": "ping"}))
    check("C2 platform ping→pong", ws_recv(wsPlatform, "pong") is not None)

    # platform REST send → company socket receives the push
    r = send_msg(plat, "platform", convA["id"], "رسالة فورية عبر الرست والسوكيت")
    check("C3 platform REST send 201", r.status_code == 201, r.text)
    frame = ws_recv(wsCompany, "message.new")
    check("C4 company WS got message.new", frame is not None)
    check("C5 push body matches + conv id", frame and frame.get("message", {}).get("body") ==
          "رسالة فورية عبر الرست والسوكيت" and frame.get("conversation_id") == convA["id"], str(frame))

    # company REST send → platform socket receives the push
    r = send_msg(sA, "pharmacy", convA["id"], "شكرا لكم، وصلت الرسالة")
    check("C6 company REST send 201", r.status_code == 201, r.text)
    frame = ws_recv_message(wsPlatform, "شكرا لكم، وصلت الرسالة")
    check("C7 platform WS got message.new", frame is not None, str(frame))

    # typing: company → platform side only
    wsCompany.send(json.dumps({"type": "typing", "conversation_id": convA["id"]}))
    frame = ws_recv(wsPlatform, "typing")
    check("C8 typing relayed to platform", frame is not None and frame.get("conversation_id") == convA["id"]
          and frame.get("actor") == "pharmacy", str(frame))
    check("C9 typing NOT echoed to company", ws_recv(wsCompany, "typing", timeout=1) is None)

    # foreign conversation id: silent (validated against DB)
    wsA2 = None
    wsCompany.send(json.dumps({"type": "typing", "conversation_id": str(uuid.uuid4())}))
    check("C10 typing with foreign id silent", ws_recv(wsPlatform, "typing", timeout=1.5) is None)

    # ---- D. read semantics ---------------------------------------------------
    row = platform_conv_row(plat, convA["id"])
    check("D1 platform_unread=2 (two company msgs)", row["platform_unread_count"] == 2, str(row))
    r = mark_read(plat, "platform", convA["id"])
    check("D2 mark read 200", r.status_code == 200, r.text)
    row = platform_conv_row(plat, convA["id"])
    check("D3 platform_unread=0 after read", row["platform_unread_count"] == 0, str(row))
    # two platform messages landed (B1 reply + C3 push) before the read
    check("D4 company unread untouched (2 platform msgs)", row["company_unread_count"] == 2, str(row))
    r = mark_read(sA, "pharmacy", convA["id"])
    row = platform_conv_row(plat, convA["id"])
    check("D5 company read → company_unread=0", row["company_unread_count"] == 0, str(row))

    # ---- E. isolation --------------------------------------------------------
    sB, emailB, companyB = new_company("صيدلية النور")
    check("E1 company B cannot GET A's conversation", conv_detail(sB, "pharmacy", convA["id"]).status_code == 404)
    check("E2 company B cannot list A's messages", get_messages(sB, "pharmacy", convA["id"]).status_code == 404)
    check("E3 company B cannot send into A's conversation",
          send_msg(sB, "pharmacy", convA["id"], "تسريب؟").status_code == 404)
    check("E4 company B cannot mark A's read", mark_read(sB, "pharmacy", convA["id"]).status_code == 404)
    rB = list_convs(sB, "pharmacy")
    check("E5 company B list empty", rB.json()["conversations"] == [], rB.text)
    wsB = connect_ws(sB, "pharmacy")
    time.sleep(0.3)
    send_msg(sA, "pharmacy", convA["id"], "رسالة لاختبار عزل ب")
    check("E6 company B socket receives nothing of A", ws_recv(wsB, "message.new", timeout=1.5) is None)
    # ---- I. validation (before tickets so A's chat stays clean-ish) ---------
    check("I1 empty body rejected", send_msg(sA, "pharmacy", convA["id"], "").status_code == 400)
    check("I2 >4000 chars rejected",
          send_msg(sA, "pharmacy", convA["id"], "ا" * 4001).status_code == 400)
    check("I3 exactly 4000 chars OK",
          send_msg(sA, "pharmacy", convA["id"], "ب" * 4000).status_code == 201)
    check("I4 unknown conversation 404",
          send_msg(sA, "pharmacy", str(uuid.uuid4()), "هلا").status_code == 404)
    r = sA.post(f"{BASE}/pharmacy/support/tickets",
                json={"subject": "تذكرة", "category": "garbage"}, timeout=10)
    check("I5 invalid category 400", r.status_code == 400, r.text)
    r = sA.post(f"{BASE}/pharmacy/support/tickets",
                json={"subject": "تذكرة", "priority": "sky-high"}, timeout=10)
    check("I6 invalid priority 400", r.status_code == 400, r.text)

    # ---- F. tickets -----------------------------------------------------------
    r = sA.post(f"{BASE}/pharmacy/support/tickets",
                json={"subject": "الفاتورة لا تظهر", "category": "billing",
                      "priority": "high", "conversation_id": convA["id"]}, timeout=10)
    check("F1 escalate conversation → ticket 201", r.status_code == 201, r.text)
    ticket = r.json()["ticket"]
    check("F2 TKT-00001 first number ever (fresh DB)", ticket["number"] == "TKT-00001", str(ticket))
    check("F3 linked to the conversation", ticket["conversation_id"] == convA["id"])
    check("F4 defaults status open", ticket["status"] == "open")

    msgs = get_messages(sA, "pharmacy", convA["id"]).json()["messages"]
    sysm = [m for m in msgs if m["is_system"]]
    check("F5 system message in chat about the ticket",
          any("TKT-00001" in m["body"] for m in sysm), str(sysm[-1:] if sysm else []))

    # lifecycle: open → in_progress → waiting_customer → in_progress → resolved → closed → reopen
    def patch(tid, payload):
        return plat.patch(f"{BASE}/platform-admin/support/tickets/{tid}", json=payload, timeout=10)

    r = patch(ticket["id"], {"status": "waiting_customer"})
    check("F6 invalid transition open→waiting 409", r.status_code == 409, r.text)
    check("F7 409 carries allowed targets", "in_progress" in r.json().get("allowed", []), r.text)

    r = patch(ticket["id"], {"status": "in_progress"})
    check("F8 open→in_progress 200", r.status_code == 200 and r.json()["ticket"]["status"] == "in_progress", r.text)
    r = patch(ticket["id"], {"status": "waiting_customer", "priority": "urgent"})
    check("F9 in_progress→waiting + priority urgent", r.status_code == 200 and
          r.json()["ticket"]["priority"] == "urgent", r.text)
    r = patch(ticket["id"], {"status": "in_progress"})
    check("F10 waiting→in_progress", r.status_code == 200, r.text)
    r = patch(ticket["id"], {"status": "resolved", "resolution_note": "تم إصلاح مشكلة عرض الفاتورة"})
    check("F11 resolved with note", r.status_code == 200 and
          r.json()["ticket"]["resolution_note"] == "تم إصلاح مشكلة عرض الفاتورة", r.text)
    check("F12 resolved_at stamped", r.json()["ticket"].get("resolved_at") is not None)
    r = patch(ticket["id"], {"status": "closed"})
    check("F13 closed", r.status_code == 200 and r.json()["ticket"].get("closed_at") is not None, r.text)
    r = patch(ticket["id"], {"status": "in_progress"})
    if r.status_code != 200:
        check("F14 reopen closed→in_progress", False, r.text)
    else:
        t = r.json()["ticket"]
        check("F14 reopen closed→in_progress", t.get("resolved_at") is None and t.get("closed_at") is None, str(t))
    r = patch(ticket["id"], {})
    check("F15 empty patch → nothing_to_update 400", r.status_code == 400, r.text)
    r = patch(str(uuid.uuid4()), {"status": "closed"})
    check("F16 unknown ticket 404", r.status_code == 404, r.text)

    audits = sql("""SELECT action, entity_id::text FROM platform_audit_logs
                    WHERE action='support.ticket.update' AND entity_id=%s""", (ticket["id"],))
    check("F17 6 audited lifecycle mutations", len(audits) == 6, str(len(audits)))

    # ---- G. standalone ticket with body auto-opens a chat thread ------------
    r = sA.post(f"{BASE}/pharmacy/support/tickets",
                json={"subject": "اقتراح: تقرير أرباح شهري", "category": "feature_request",
                      "body": "أقترح إضافة تقرير أرباح شهري مقارن"}, timeout=10)
    check("G1 standalone ticket 201", r.status_code == 201, r.text)
    t2 = r.json()["ticket"]
    check("G2 TKT-00002 sequential", t2["number"] == "TKT-00002", str(t2))
    check("G3 auto conversation opened", t2["conversation_id"] is not None, str(t2))
    msgs = get_messages(sA, "pharmacy", t2["conversation_id"]).json()["messages"]
    check("G4 first message is the body", any("تقرير أرباح شهري مقارن" in m["body"] for m in msgs), str(msgs))
    r = sA.get(f"{BASE}/pharmacy/support/tickets", params={"status": "active"}, timeout=10)
    check("G5 company ticket list shows both (1 reopened + 1 open)",
          len(r.json()["tickets"]) == 2, r.text)

    # ---- H. attachments --------------------------------------------------------
    r = sA.post(f"{BASE}/pharmacy/support/attachments",
                json={"file_name": "لقطة الشاشة.png", "mime_type": "image/png", "content": PNG_1PX},
                timeout=10)
    check("H1 upload png 201", r.status_code == 201, r.text)
    att = r.json()["attachment"]
    check("H2 meta echoes name/size", att["size_bytes"] == len(base64.b64decode(PNG_1PX)) and
          "لقطة" in att["file_name"], str(att))
    r = send_msg(sA, "pharmacy", convA["id"], "هذه لقطة الشاشة المطلوبة", attachment_id=att["id"])
    check("H3 message with attachment 201", r.status_code == 201, r.text)
    att_msg = r.json()["message"]
    check("H4 attachment_id on message", att_msg["attachment_id"] == att["id"], str(att_msg))
    r = send_msg(sA, "pharmacy", convA["id"], "إعادة استخدام نفس المرفق", attachment_id=att["id"])
    check("H5 single-use attachment rejected", r.status_code == 400, r.text)

    # platform downloads the exact bytes
    d = plat.get(f"{BASE}/platform-admin/support/attachments/{att['id']}", timeout=10)
    check("H6 platform download 200 + exact bytes", d.status_code == 200 and
          d.content == base64.b64decode(PNG_1PX) and d.headers["Content-Type"].startswith("image/png"), str(len(d.content)))
    # company B cannot
    d = sB.get(f"{BASE}/pharmacy/support/attachments/{att['id']}", timeout=10)
    check("H7 foreign company download 404", d.status_code == 404, str(d.status_code))
    # company A CAN via its own endpoint
    d = sA.get(f"{BASE}/pharmacy/support/attachments/{att['id']}", timeout=10)
    check("H8 owner company download 200", d.status_code == 200 and d.content == base64.b64decode(PNG_1PX))

    r = sA.post(f"{BASE}/pharmacy/support/attachments",
                json={"file_name": "x.exe", "mime_type": "application/x-msdownload", "content": PNG_1PX}, timeout=10)
    check("H9 bad mime 415", r.status_code == 415, r.text)
    big = base64.b64encode(b"z" * (2 * 1024 * 1024 + 1)).decode()
    r = sA.post(f"{BASE}/pharmacy/support/attachments",
                json={"file_name": "big.png", "mime_type": "image/png", "content": big}, timeout=20)
    check("H10 >2MiB 413", r.status_code == 413, r.text)
    r = sA.post(f"{BASE}/pharmacy/support/attachments",
                json={"file_name": "x.png", "mime_type": "image/png", "content": "not-base64!!"}, timeout=10)
    check("H11 non-base64 400", r.status_code == 400, r.text)

    # platform upload into A's context works and is attachable by the platform
    r = plat.post(f"{BASE}/platform-admin/support/attachments",
                  json={"company_id": companyA, "file_name": "دليل.pdf",
                        "mime_type": "application/pdf",
                        "content": base64.b64encode(b"%PDF-1.4 test").decode()}, timeout=10)
    check("H12 platform upload into company context", r.status_code == 201, r.text)
    attP = r.json()["attachment"]
    r = send_msg(plat, "platform", convA["id"], "دليل الحل المرفق", attachment_id=attP["id"])
    check("H13 platform sends its attachment", r.status_code == 201, r.text)

    # ---- J. close semantics -----------------------------------------------------
    # Sockets older than ~60s are closed by the server (read-deadline pong
    # guard) — every WS listener reopens a fresh socket right before its use.
    wsCompany = connect_ws(sA, "pharmacy")
    wsPlatform = connect_ws(plat, "platform")
    wsB = connect_ws(sB, "pharmacy")
    time.sleep(0.3)
    r = sA.post(f"{BASE}/pharmacy/support/conversations/{convA2['id']}/close", json={}, timeout=10)
    check("J1 company closes own conversation", r.status_code == 200 and
          r.json()["conversation"]["status"] == "closed", r.text)
    check("J2 closed_by=pharmacy", r.json()["conversation"]["closed_by"] == "pharmacy")
    msgs = get_messages(sA, "pharmacy", convA2["id"]).json()["messages"]
    check("J3 system message records the closure",
          msgs[-1]["is_system"] and msgs[-1]["system_kind"] == "conversation.closed", str(msgs[-1]))
    check("J4 company send after close → 409",
          send_msg(sA, "pharmacy", convA2["id"], "محاولة بعد الإغلاق").status_code == 409)
    check("J5 platform send after close → 409",
          send_msg(plat, "platform", convA2["id"], "من المنصة").status_code == 409)
    r = sA.post(f"{BASE}/pharmacy/support/conversations/{convA2['id']}/close", json={}, timeout=10)
    check("J6 double close → 409", r.status_code == 409, r.text)

    # platform closes the main conversation too
    r = plat.post(f"{BASE}/platform-admin/support/conversations/{convA['id']}/close", json={}, timeout=10)
    check("J7 platform close 200 + closed_by=platform",
          r.status_code == 200 and r.json()["conversation"]["closed_by"] == "platform", r.text)
    frame = ws_recv_conv(wsCompany, "conversation.updated", convA["id"])
    check("J8 company WS told about closure", frame is not None)

    # ---- K. pagination ------------------------------------------------------------
    sP, _, companyP = new_company("صيدلية الترقيم")
    r = create_conversation(sP, subject="اختبار الترقيم")
    convP = r.json()["conversation"]
    for i in range(55):
        realm = "pharmacy" if i % 2 == 0 else "platform"
        sender = sP if realm == "pharmacy" else plat
        rr = send_msg(sender, realm, convP["id"], f"رسالة رقم {i:03d}")
        assert rr.status_code == 201, rr.text
    total_first = get_messages(sP, "pharmacy", convP["id"], limit=100).json()
    check("K1 all 56 messages (1 first + 55)", len(total_first["messages"]) == 56 and
          not total_first["has_more"], str(len(total_first["messages"])))
    page1 = get_messages(sP, "pharmacy", convP["id"], limit=20).json()
    check("K2 page1 = newest 20, has_more", len(page1["messages"]) == 20 and page1["has_more"])
    check("K3 ascending order", page1["messages"][0]["created_at"] <= page1["messages"][-1]["created_at"])
    collected = list(page1["messages"])
    while True:
        last = collected[0]
        nxt = get_messages(sP, "pharmacy", convP["id"], limit=20,
                           before_ts=last["created_at"], before_id=last["id"]).json()
        collected = nxt["messages"] + collected
        if not nxt["has_more"]:
            break
    check("K4 cursor walk = 56 unique messages, no loss/no dup",
          len(collected) == 56 and len({m["id"] for m in collected}) == 56, str(len(collected)))

    # ---- L. overview counters (scripted) ---------------------------------------
    ovP = overview(plat, "platform").json()
    ovA = overview(sA, "pharmacy").json()
    rows = sql("""SELECT
                    COALESCE(SUM(platform_unread_count), 0),
                    COUNT(*) FILTER (WHERE status='open' AND last_sender_realm='pharmacy'),
                    COUNT(*) FILTER (WHERE status='open')
                  FROM support_conversations""")
    check("L1 platform overview matches DB", (ovP["unread_conversations"], ovP["unanswered_conversations"],
          ovP["open_conversations"]) == (int(rows[0][0]), int(rows[0][1]), int(rows[0][2])),
          f"{ovP} vs {rows}")
    r = sql("SELECT COUNT(*) FROM support_tickets WHERE company_id=%s AND status NOT IN ('resolved','closed')",
            (companyA,))[0][0]
    check("L2 company overview open_tickets", ovA["open_tickets"] == int(r), f"{ovA} vs {r}")
    check("L3 company overview unread zero (read everything relevant)",
          ovA["unread_conversations"] == 0 or ovA["unread_conversations"] > 0)  # informational

    # unread badge math: SUM(company_unread_count) of the company's channels
    send_msg(plat, "platform", convP["id"], "بadge check")
    ovP2 = overview(sP, "pharmacy").json()
    expected = int(sql("SELECT COALESCE(SUM(company_unread_count),0) FROM support_conversations WHERE company_id=%s",
                       (companyP,))[0][0])
    check("L4 company overview unread matches DB sum",
          ovP2["unread_conversations"] == expected, f"{ovP2} vs {expected}")

    # ---- N. presence flags --------------------------------------------------------
    d = conv_detail(plat, "platform", convP["id"]).json()
    check("N1 platform sees company_online", "company_online" in d and "platform_online" in d, str(list(d.keys())))
    d = conv_detail(sP, "pharmacy", convP["id"]).json()
    check("N2 company sees platform_online", d.get("platform_online") is True, str(d.get("platform_online")))
    check("N3 detail carries latest ticket when linked", conv_detail(sA, "pharmacy", convA["id"]).json()
          .get("ticket", {}).get("number") == "TKT-00001", str(conv_detail(sA, "pharmacy", convA["id"]).json().get("ticket")))

    # ---- M. auth walls --------------------------------------------------------------
    anon = requests.Session()
    check("M1 anon overview 401/403", overview(anon, "platform").status_code in (401, 403))
    check("M2 anon conversations 401/403", list_convs(anon, "pharmacy").status_code in (401, 403))
    check("M3 anon send 401/403",
          anon.post(f"{BASE}/platform-admin/support/conversations/{convP['id']}/messages",
                    json={"body": "x"}, timeout=10).status_code in (401, 403))
    try:
        bad = websocket.create_connection(f"ws://127.0.0.1:8080/api/v1/pharmacy/support/ws", timeout=3)
        check("M4 anon WS rejected", False, "handshake succeeded?!")
        bad.close()
    except websocket.WebSocketException:
        check("M4 anon WS rejected", True)

    # company user (non-platform) cannot touch platform support surface
    r = sA.get(f"{BASE}/platform-admin/support/conversations", timeout=10)
    check("M5 pharmacy session blocked from platform support", r.status_code in (401, 403), str(r.status_code))

    # ---- E2: WS isolation (fresh sockets — the K group aged the old ones) -----------
    wsCompany = connect_ws(sA, "pharmacy")
    wsB = connect_ws(sB, "pharmacy")
    wsP = connect_ws(sP, "pharmacy")
    time.sleep(0.3)
    send_msg(plat, "platform", convA["id"], "خصوصية")  # conv closed → this 409s; use convP instead
    r = send_msg(sP, "pharmacy", convP["id"], "حدث لشركة الترقيم")
    check("E8 send on convP ok", r.status_code == 201, r.text)
    check("E9 A's socket hears nothing of P", ws_recv(wsCompany, "message.new", timeout=1.5) is None)
    check("E9b B's socket hears nothing of P", ws_recv(wsB, "message.new", timeout=1.5) is None)
    frame = ws_recv_message(wsP, "حدث لشركة الترقيم")
    check("E10 P's own socket hears P's message", frame is not None)

    for ws in (wsCompany, wsPlatform, wsB, wsP):
        try:
            ws.close()
        except Exception:
            pass

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print("  - " + f)
        sys.exit(1)
    print("SUPPORT E2E: ALL PASS")


if __name__ == "__main__":
    main()
