#!/usr/bin/env bash
# تسuite الاختبارات الرجعية الكاملة لنظام الصلاحيات (Task 42) — كل شيء في نفس
# استدعاء shell (قاعدة البيئة: الخلفيات تُقتل بين الاستدعاءات).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export PATH="/home/z/.venv/bin:$PATH"
export GOTOOLCHAIN=auto CGO_ENABLED=0 GOFLAGS=-mod=vendor
export DATABASE_URL="${E2E_DATABASE_URL:-postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable}"

echo "== PostgreSQL =="
LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata status >/dev/null 2>&1 \
  || LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata -o "-p 54329 -k /tmp" -l /home/z/pgdata/log.txt start >/dev/null 2>&1
for _ in $(seq 1 20); do /tmp/pg17/bin/pg_ctl -D /home/z/pgdata status >/dev/null 2>&1 && break; sleep 0.5; done

# تكرارية التشغيل: نبدأ دائمًا من سيناريو print_seed على قاعدة fresh
# (test_reports في نهاية التشغيل يعيد القاعدة لسيناريوه هو، فنصلحها هنا)
bash scripts/reset_reports_test_db.sh || exit 1

echo "== Backend =="
(cd backend && /tmp/go/bin/go build -o /tmp/pharmacy-backend ./cmd/server) || exit 1
pkill -f pharmacy-backend 2>/dev/null; sleep 0.5
setsid nohup /tmp/pharmacy-backend > /tmp/backend.log 2>&1 &
for _ in $(seq 1 40); do curl -s -o /dev/null --max-time 2 http://localhost:8080/api/v1/health && break; sleep 0.5; done
curl -s -o /dev/null -w "backend: %{http_code}\n" --max-time 3 http://localhost:8080/api/v1/health

echo "== Frontend =="
if ! curl -s -o /dev/null --max-time 3 http://localhost:3000/login; then
  (cd frontend/apps/pharmacy-app && setsid nohup npm run dev > /tmp/frontend.log 2>&1 &)
fi
for _ in $(seq 1 60); do curl -s -o /dev/null --max-time 3 http://localhost:3000/login && break; sleep 1; done
# تسخين كل مسارات اللوحة (next dev يترجم على الطاير)
for u in / /inventory /pos /sales /customers /inventory/movements /employees /attendance /branches /reports /reports/sales /reports/inventory /reports/movements /inventory/new /settings /settings/receipts /settings/import /login; do
  curl -s -o /dev/null --max-time 60 "http://localhost:3000$u"
done
curl -s -o /dev/null -w "frontend: %{http_code}\n" --max-time 30 http://localhost:3000/login

python3 scripts/seed_search_fixtures.py >/dev/null 2>&1

STATUS=0
run_suite() {
  local name="$1"; shift
  echo ""
  echo "======== $name ========"
  if "$@" > "/tmp/reg_$(echo "$name" | tr ' /' '__').txt" 2>&1; then
    tail -1 "/tmp/reg_$(echo "$name" | tr ' /' '__').txt"
  else
    echo "FAILED — آخر الأسطر:"
    grep -E "\[FAIL\]|Error|Traceback" "/tmp/reg_$(echo "$name" | tr ' /' '__').txt" | head -5
    tail -3 "/tmp/reg_$(echo "$name" | tr ' /' '__').txt"
    STATUS=1
  fi
}

run_suite "permissions_e2e"        python3 scripts/permissions_e2e.py
run_suite "sales_features"         python3 scripts/sales_features_e2e.py
run_suite "pos_receipt"            python3 scripts/pos_receipt_e2e.py
run_suite "product_import"         python3 scripts/product_import_e2e.py
run_suite "product_import_ui"      python3 scripts/product_import_ui_e2e.py
run_suite "test_inventory_moves"   python3 scripts/test_inventory_movements.py

# test_reports يدير خادمه المستقل على قاعدة fresh — يجب إيقاف باكند 8080 أولًا
echo ""
echo "======== test_reports ========"
pkill -f pharmacy-backend 2>/dev/null; sleep 1
if python3 scripts/test_reports.py > /tmp/reg_test_reports.txt 2>&1; then
  tail -1 /tmp/reg_test_reports.txt
else
  echo "FAILED — آخر الأسطر:"
  grep -E "\[FAIL\]|Error|Traceback" /tmp/reg_test_reports.txt | head -5
  tail -3 /tmp/reg_test_reports.txt
  STATUS=1
fi

echo ""
if [ $STATUS -eq 0 ]; then echo "ALL REGRESSION SUITES PASSED"; else echo "SOME SUITES FAILED"; fi
exit $STATUS
