#!/usr/bin/env bash
# E2E نظام ترحيل المنتجات: باكند + تسخين الواجهة + اختبار API ثم اختبار UI
# — كل شيء في نفس استدعاء shell (قاعدة البيئة: الخلفيات تُقتل بين الاستدعاءات).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export PATH="/home/z/.venv/bin:$PATH"
export GOTOOLCHAIN=auto CGO_ENABLED=0 GOFLAGS=-mod=vendor
export DATABASE_URL="${E2E_DATABASE_URL:-postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable}"
LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata status >/dev/null 2>&1 \
  || LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata -o "-p 54329 -k /tmp" -l /home/z/pgdata/log.txt start >/dev/null 2>&1

echo "== بناء الباكند =="
(cd backend && /tmp/go/bin/go build -o /tmp/pharmacy-backend ./cmd/server) || exit 1
pkill -f pharmacy-backend 2>/dev/null; sleep 0.5

echo "== تشغيل الباكند على 8080 =="
setsid nohup /tmp/pharmacy-backend > /tmp/backend.log 2>&1 &
for _ in $(seq 1 40); do
  curl -s -o /dev/null --max-time 2 http://localhost:8080/api/v1/health && break
  sleep 0.5
done
curl -s -o /dev/null -w "backend health: %{http_code}\n" --max-time 3 http://localhost:8080/api/v1/health

if ! curl -s -o /dev/null --max-time 3 http://localhost:3000/login; then
  echo "== تشغيل واجهة next dev =="
  (cd frontend/apps/pharmacy-app && setsid nohup npm run dev > /tmp/frontend.log 2>&1 &)
fi

echo "== تسخين الواجهة =="
for path in "/login" "/settings" "/settings/import" "/pos" "/inventory"; do
  curl -s -o /dev/null --max-time 60 "http://localhost:3000${path}"
done
curl -s -o /dev/null -w "app warm: %{http_code}\n" --max-time 30 http://localhost:3000/login

echo "== E2E API: استيراد المنتجات =="
python3 scripts/product_import_e2e.py
API_STATUS=$?

echo "== E2E UI: معالج الترحيل =="
python3 scripts/product_import_ui_e2e.py
UI_STATUS=$?

pkill -f pharmacy-backend 2>/dev/null
[ "$API_STATUS" -eq 0 ] && [ "$UI_STATUS" -eq 0 ] || exit 1
exit 0
