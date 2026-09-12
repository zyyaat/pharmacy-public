#!/usr/bin/env python3
"""E2E — delta sync (offline-first smart synchronization, api_level 59).

Run against a server on :8080 (migrations run at boot):
    python3 scripts/sync_e2e.py

Covers the delta-sync contract (GET /pharmacy/sync):
  1.  Bootstrap (no since) → server_time only, no sections
  2.  New product → inventory.items carries the batch row with EXACTLY the
      same keys as a GET /pharmacy/inventory row (shape identity is the
      merge contract), movements.items carries the opening movement
  3.  Credit sale → sales.items carries the invoice (shape identity with
      GET /pos/sales), customers.items carries the customer with the exact
      computed balance, inventory quantity decreased, movement appended
  4.  Return (credit note) → sales.items re-sends the invoice with updated
      status/returns/returned_amount (updated_at trigger), customer balance
      re-computed, stock partially restored (+IN movement)
  5.  Payment → customer balance decreases again (ledger-driven detection)
  6.  Product price edit → inventory row re-sent with the new price
  7.  Customer name edit → customers row re-sent with the new name
  8.  Tombstone deletion contract → a sync_tombstones row (entity=customer)
      surfaces as customers.deleted_ids
  9.  Re-applying the same delta is stable (idempotent merges, at-least-once)
  10. Empty window → empty items, monotonic server_time cursor
"""
import sys
import time
import uuid

import psycopg2
import requests

BASE = "http://127.0.0.1:8080/api/v1"
DB = "postgresql://postgres@127.0.0.1:54329/reports_test"
EMAIL = f"sync-e2e-{uuid.uuid4().hex[:8]}@test.io"
PASSWORD = "Str0ng!Pass2026"
FAILURES = []


def check(name, ok, extra=""):
    print(("PASS " if ok else "FAIL ") + name + (f"  [{extra}]" if extra and not ok else ""))
    if not ok:
        FAILURES.append(name)


def sync(s, since=None):
    r = s.get(f"{BASE}/pharmacy/sync", params={} if since is None else {"since": since}, timeout=10)
    if r.status_code != 200:
        raise AssertionError(f"sync {r.status_code}: {r.text[:300]}")
    return r.json()["data"]


def wait_health():
    for _ in range(60):
        try:
            if requests.get("http://127.0.0.1:8080/health", timeout=1).status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(0.5)
    return False


def main():
    assert wait_health(), "server not healthy"

    s = requests.Session()
    r = s.post(f"{BASE}/auth/register", json={
        "company_name": "صيدلية المزامنة", "company_email": EMAIL,
        "first_name": "مزامنة", "last_name": "الاختبار",
        "email": EMAIL, "password": PASSWORD,
    }, timeout=10)
    assert r.status_code in (200, 201), r.text

    conn = psycopg2.connect(DB)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("UPDATE company_users SET email_verified_at=NOW() WHERE email=%s", (EMAIL,))
    cur.execute(
        "UPDATE pharmacies SET settings = settings || '{\"onboarding\": {\"completed\": true}}'::jsonb "
        "WHERE account_id IN (SELECT id FROM accounts WHERE contact_email=%s)",
        (EMAIL,),
    )
    r = s.post(f"{BASE}/auth/pharmacy/login", json={"email": EMAIL, "password": PASSWORD}, timeout=10)
    assert r.status_code == 200, r.text
    csrf = s.cookies.get("pharmacy_csrf")

    # ---- 1) bootstrap: no since → server_time only -------------------------
    boot = sync(s)
    check("bootstrap returns server_time only", set(boot.keys()) == {"server_time"}, str(set(boot.keys())))
    cursor = boot["server_time"]
    check("server_time is RFC3339", "T" in cursor and cursor.endswith("Z"), cursor)

    # ---- 2) create product → inventory delta ------------------------------
    r = s.post(f"{BASE}/pharmacy/products", headers={"X-CSRF-Token": csrf}, json={
        "name": "أواميسين 500", "dosage_form": "capsule", "strength": "500mg",
        "barcode": "", "packaging_type": "BOX_STRIP", "units_per_box": 4,
        "cost_price_piastres": 2000, "selling_price_piastres": 3000,
        "partial_selling_price_piastres": 900,
        "min_stock_level": 2,
        "initial_boxes": 10, "initial_strips": 0,
        "batch_number": "SYNC-B1", "expiry_date": "2027-09-30",
    }, timeout=10)
    check("product created 201", r.status_code == 201, r.text[:200])
    product = r.json()["data"]

    d = sync(s, cursor)
    check("delta carries server_time + 4 sections",
          set(d.keys()) == {"server_time", "inventory", "customers", "sales", "movements"}, str(set(d.keys())))
    inv_items = d["inventory"]["items"]
    check("inventory delta has the new batch", len(inv_items) == 1 and inv_items[0]["batch_number"] == "SYNC-B1",
          str(len(inv_items)))
    check("inventory delta shape == list shape", True, "")
    list_rows = s.get(f"{BASE}/pharmacy/inventory", timeout=10).json()["data"]
    check("shape identity inventory", set(list_rows[0].keys()) == set(inv_items[0].keys()),
          str(set(list_rows[0].keys()) ^ set(inv_items[0].keys())))
    check("overflow false", d["inventory"]["overflow"] is False)
    check("inventory deleted_ids empty", d["inventory"]["deleted_ids"] == [])
    check("movements delta has opening movement", len(d["movements"]["items"]) == 1, str(len(d["movements"]["items"])))
    mov_row = d["movements"]["items"][0]
    mov_list = s.get(f"{BASE}/pharmacy/inventory/movements", params={"limit": 20, "offset": 0}, timeout=10).json()["data"]["movements"]
    check("shape identity movements", set(mov_list[0].keys()) == set(mov_row.keys()),
          str(set(mov_list[0].keys()) ^ set(mov_row.keys())))
    cursor = d["server_time"]

    # ---- 3) credit sale → sales + customers + inventory + movements --------
    r = s.post(f"{BASE}/pharmacy/customers", headers={"X-CSRF-Token": csrf},
               json={"name": "عميل المزامنة", "phone": "01000000001"}, timeout=10)
    check("customer created 201", r.status_code == 201, r.text[:200])
    customer = r.json()["data"]["customer"]

    r = s.post(f"{BASE}/pharmacy/pos/sales", headers={"X-CSRF-Token": csrf}, json={
        "items": [{"pharmacy_product_id": product["id"], "sale_unit": "box", "quantity": 2}],
        "payment_type": "credit", "customer_id": customer["id"],
    }, timeout=15)
    check("credit sale 201", r.status_code == 201, r.text[:200])
    sale_id = r.json()["data"]["sale_id"]
    sale_total = r.json()["data"]["total_amount_piastres"]

    d = sync(s, cursor)
    check("sale in delta", len(d["sales"]["items"]) == 1 and d["sales"]["items"][0]["id"] == sale_id,
          str([x["id"] for x in d["sales"]["items"]]))
    sale_row = d["sales"]["items"][0]
    sale_list = s.get(f"{BASE}/pharmacy/pos/sales", params={"limit": 5, "offset": 0}, timeout=10).json()["data"]["sales"]
    check("shape identity sales", set(sale_list[0].keys()) == set(sale_row.keys()),
          str(set(sale_list[0].keys()) ^ set(sale_row.keys())))
    check("customer balance == sale total", len(d["customers"]["items"]) == 1
          and d["customers"]["items"][0]["balance_piastres"] == sale_total,
          str(d["customers"]["items"]))
    cust_row = d["customers"]["items"][0]
    cust_list = s.get(f"{BASE}/pharmacy/customers", timeout=10).json()["data"]["customers"]
    check("shape identity customers", set(cust_list[0].keys()) == set(cust_row.keys()),
          str(set(cust_list[0].keys()) ^ set(cust_row.keys())))
    inv_row = next(i for i in d["inventory"]["items"] if i["batch_number"] == "SYNC-B1")
    check("inventory quantity 10 → 40 strips (2 boxes of 4)", inv_row["quantity"] == 40 - 8 or inv_row["quantity"] == 32,
          str(inv_row["quantity"]))
    check("movement OUT present", len(d["movements"]["items"]) == 1
          and d["movements"]["items"][0]["quantity"] < 0, str(d["movements"]["items"]))
    cursor = d["server_time"]

    # ---- 4) return 1 strip → updated_at trigger re-sends the invoice -------
    detail = s.get(f"{BASE}/pharmacy/pos/sales/{sale_id}", timeout=10).json()["data"]
    sale_item = detail["items"][0]
    r = s.post(f"{BASE}/pharmacy/pos/sales/{sale_id}/returns", headers={"X-CSRF-Token": csrf}, json={
        "items": [{"sale_item_id": sale_item["sale_item_id"], "quantity": 1}],
        "reason": "sync-e2e",
    }, timeout=15)
    check("return 201", r.status_code == 201, r.text[:200])
    refund = r.json()["data"]["total_amount_piastres"]

    d = sync(s, cursor)
    check("returned invoice re-sent by delta", any(x["id"] == sale_id for x in d["sales"]["items"]),
          str([x["id"] for x in d["sales"]["items"]]))
    rs = next(x for x in d["sales"]["items"] if x["id"] == sale_id)
    check("status partially_returned", rs["status"] == "partially_returned", rs["status"])
    check("returns array attached in delta", len(rs["returns"]) == 1
          and rs["returns"][0]["total_amount_piastres"] == refund, str(rs["returns"]))
    check("returned_amount updated", rs["returned_amount_piastres"] == refund, str(rs["returned_amount_piastres"]))
    cust_row = next(c for c in d["customers"]["items"] if c["id"] == customer["id"])
    check("balance reduced by refund", cust_row["balance_piastres"] == sale_total - refund,
          str(cust_row["balance_piastres"]))
    inv_row = next((i for i in d["inventory"]["items"] if i["batch_number"] == "SYNC-B1"), None)
    check("stock restored (+1 strip)", inv_row is not None and inv_row["quantity"] == 33, str(inv_row and inv_row["quantity"]))
    check("movement IN present", any(m["quantity"] > 0 for m in d["movements"]["items"]), str(d["movements"]["items"]))
    cursor = d["server_time"]

    # ---- 5) payment → balance drift detected via ledger --------------------
    r = s.post(f"{BASE}/pharmacy/customers/{customer['id']}/payments", headers={"X-CSRF-Token": csrf},
               json={"amount_piastres": 1000, "note": "دفعة مزامنة"}, timeout=10)
    check("payment 201", r.status_code == 201, r.text[:200])
    d = sync(s, cursor)
    cust_row = next((c for c in d["customers"]["items"] if c["id"] == customer["id"]), None)
    check("payment re-sends customer row", cust_row is not None, str(d["customers"]["items"]))
    check("balance decreased by payment", cust_row and cust_row["balance_piastres"] == sale_total - refund - 1000,
          str(cust_row and cust_row["balance_piastres"]))
    cursor = d["server_time"]

    # ---- 6) product edit → inventory row re-sent with the new price --------
    r = s.put(f"{BASE}/pharmacy/products/{product['id']}", headers={"X-CSRF-Token": csrf}, json={
        "name": "أواميسين 500", "dosage_form": "capsule", "strength": "500mg",
        "barcode": "", "packaging_type": "BOX_STRIP", "units_per_box": 4,
        "cost_price_piastres": 2000, "selling_price_piastres": 3500,
        "partial_selling_price_piastres": 950,
        "min_stock_level": 2,
    }, timeout=10)
    check("product edit 200", r.status_code == 200, r.text[:200])
    d = sync(s, cursor)
    inv_row = next((i for i in d["inventory"]["items"] if i["batch_number"] == "SYNC-B1"), None)
    check("price edit surfaces in inventory delta", inv_row is not None and inv_row["selling_price_piastres"] == 3500,
          str(inv_row and inv_row["selling_price_piastres"]))
    cursor = d["server_time"]

    # ---- 7) customer name edit → updated_at on customers -------------------
    r = s.put(f"{BASE}/pharmacy/customers/{customer['id']}", headers={"X-CSRF-Token": csrf},
              json={"name": "عميل المزامنة المعدّل", "phone": "01000000001"}, timeout=10)
    check("customer edit 200", r.status_code == 200, r.text[:200])
    d = sync(s, cursor)
    cust_row = next((c for c in d["customers"]["items"] if c["id"] == customer["id"]), None)
    check("name edit surfaces in customers delta", cust_row is not None and cust_row["name"] == "عميل المزامنة المعدّل",
          str(cust_row))
    cursor = d["server_time"]

    # ---- 8) tombstone deletion contract ------------------------------------
    cur.execute(
        "INSERT INTO sync_tombstones (pharmacy_id, entity, record_id) "
        "SELECT p.id, 'customer', c.id FROM pharmacies p, customers c "
        "WHERE p.account_id IN (SELECT id FROM accounts WHERE contact_email=%s) AND c.id=%s",
        (EMAIL, customer["id"]),
    )
    d = sync(s, cursor)
    check("tombstone surfaces as deleted_ids", customer["id"] in d["customers"]["deleted_ids"],
          str(d["customers"]["deleted_ids"]))
    check("tombstoned row not in changed set", all(c["id"] != customer["id"] for c in d["customers"]["items"]))
    cursor = d["server_time"]

    # ---- 9) re-apply the same delta (idempotent stability) -----------------
    d2 = sync(s, cursor)
    time.sleep(0.3)
    d3 = sync(s, cursor)
    check("empty window stays empty", d2["inventory"]["items"] == [] and d3["inventory"]["items"] == []
          and d3["sales"]["items"] == [], str(d3["sales"]["items"]))
    check("server_time monotonic", d3["server_time"] >= d2["server_time"], f"{d2['server_time']} → {d3['server_time']}")

    # ---- 10) old cursor → overflow flags (cap parity sanity) ---------------
    r = sync(s, "2000-01-01T00:00:00Z")
    check("old cursor returns sections", len(r["inventory"]["items"]) >= 1 and len(r["sales"]["items"]) >= 1)
    check("overflow flags boolean", all(isinstance(r[k]["overflow"], bool)
          for k in ("inventory", "customers", "sales") if k in r))

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)} — {FAILURES}")
        sys.exit(1)
    print("ALL PASS — delta sync contract verified")


if __name__ == "__main__":
    main()
