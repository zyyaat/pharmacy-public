#!/usr/bin/env bash
# E2E إعدادات الفاتورة: باكند fresh + تسخين الواجهة + الاختبار — كل شيء في نفس
# استدعاء shell لأن الخلفيات تُقتل بين الاستدعاءات (قاعدة بيئة معروفة).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export GOTOOLCHAIN=auto CGO_ENABLED=0 GOFLAGS=-mod=vendor
# الكونتينر يحمل DATABASE_URL محيطياً لمشروع آخر (SQLite) — نثبّت رابط الاختبار المحلي صراحة
export DATABASE_URL="${E2E_DATABASE_URL:-postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable}"
GO=/tmp/go/bin/go
[ -x "$GO" ] || GO=$(command -v go)

echo "== بناء الباكند =="
(cd backend && "$GO" build -o /tmp/pharmacy-backend ./cmd/server) || exit 1

echo "== تشغيل الباكند على 8080 =="
/tmp/pharmacy-backend &
BACK_PID=$!
trap 'kill $BACK_PID 2>/dev/null' EXIT

for _ in $(seq 1 40); do
  curl -s -o /dev/null --max-time 2 http://localhost:8080/api/v1/health && break
  sleep 0.5
done
curl -s -o /dev/null -w "backend health: %{http_code}\n" --max-time 3 http://localhost:8080/api/v1/health

echo "== تسخين الواجهة (next dev يترجم المسارات على الطاير) =="
curl -s -o /dev/null --max-time 60 http://localhost:3000/login
curl -s -o /dev/null --max-time 60 http://localhost:3000/settings
curl -s -o /dev/null --max-time 60 http://localhost:3000/pos
curl -s -o /dev/null --max-time 60 http://localhost:3000/inventory
curl -s -o /dev/null --max-time 60 "http://localhost:3000/inventory/edit/warmup"
curl -s -o /dev/null --max-time 60 http://localhost:3000/inventory/new
curl -s -o /dev/null -w "app warm: %{http_code}\n" --max-time 30 http://localhost:3000/login

echo "== E2E: إعدادات الفاتورة والطباعة =="
python3 "${1:-scripts/pos_receipt_e2e.py}"
STATUS=$?
kill $BACK_PID 2>/dev/null
exit $STATUS
