#!/usr/bin/env bash
# E2E تطبيق نقطة البيع المستقل — كل الخدمات والاختبار في نفس استدعاء shell
# (قاعدة البيئة: الخلفيات تُقتل بين الاستدعاءات).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export PATH="/home/z/.venv/bin:$PATH"
export GOTOOLCHAIN=auto CGO_ENABLED=0 GOFLAGS=-mod=vendor
export DATABASE_URL="${E2E_DATABASE_URL:-postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable}"
# Task 56: bootstrap مدير المنصة (يستخدمه قسم 12 لاختبار نقطة تشخيص تسليم
# البريد المحمية بجلسة المنصة). bootstrap idempotent — آمن مع قاعدة fresh.
export BOOTSTRAP_SUPER_ADMIN_EMAIL="${BOOTSTRAP_SUPER_ADMIN_EMAIL:-e2e-admin@pharmacyos.test}"
export BOOTSTRAP_SUPER_ADMIN_PASSWORD="${BOOTSTRAP_SUPER_ADMIN_PASSWORD:-E2eAdmin#2026}"

echo "== PostgreSQL =="
LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata status >/dev/null 2>&1 \
  || LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata -o "-p 54329 -k /tmp" -l /home/z/pgdata/log.txt start >/dev/null 2>&1
for _ in $(seq 1 20); do /tmp/pg17/bin/pg_ctl -D /home/z/pgdata status >/dev/null 2>&1 && break; sleep 0.5; done

# تكرارية التشغيل: نبدأ دائمًا من سيناريو print_seed على قاعدة fresh
# (test_reports يترك القاعدة بسيناريو آخر فلا يوجد print-test@test.io)
bash scripts/reset_reports_test_db.sh || exit 1

echo "== Backend (8080) =="
(cd backend && /tmp/go/bin/go build -o /tmp/pharmacy-backend ./cmd/server) || exit 1
pkill -f pharmacy-backend 2>/dev/null; sleep 0.5
setsid nohup /tmp/pharmacy-backend > /tmp/backend.log 2>&1 &
for _ in $(seq 1 40); do curl -s -o /dev/null --max-time 2 http://localhost:8080/api/v1/health && break; sleep 0.5; done
curl -s -o /dev/null -w "backend: %{http_code}\n" --max-time 3 http://localhost:8080/api/v1/health

echo "== POS app (3001) =="
pkill -f "next.*3001" 2>/dev/null; sleep 0.5
(cd frontend/apps/pos-app && PORT=3001 setsid nohup npx next dev -p 3001 > /tmp/posapp.log 2>&1 &)
for _ in $(seq 1 60); do curl -s -o /dev/null --max-time 3 http://localhost:3001/login && break; sleep 1; done
# تسخين مسارات التطبيق الجديد (next dev يترجم على الطاير)
for u in / /pos /sales /login /inventory /inventory/new /inventory/movements; do
  curl -s -o /dev/null --max-time 60 "http://localhost:3001$u"
done
curl -s -o /dev/null -w "pos-app: %{http_code}\n" --max-time 30 http://localhost:3001/login

echo "== Main app (3000) =="
if ! curl -s -o /dev/null --max-time 3 http://localhost:3000/login; then
  (cd frontend/apps/pharmacy-app && setsid nohup npm run dev > /tmp/frontend.log 2>&1 &)
  for _ in $(seq 1 60); do curl -s -o /dev/null --max-time 3 http://localhost:3000/login && break; sleep 1; done
fi
curl -s -o /dev/null --max-time 30 "http://localhost:3000/pos"
curl -s -o /dev/null --max-time 60 "http://localhost:3000/branches"
curl -s -o /dev/null --max-time 60 "http://localhost:3000/branches/new"
curl -s -o /dev/null --max-time 60 "http://localhost:3000/settings/database"
curl -s -o /dev/null -w "main-app: %{http_code}\n" --max-time 30 http://localhost:3000/login

python3 scripts/seed_search_fixtures.py >/dev/null 2>&1

echo ""
echo "======== pos_app_e2e ========"
timeout 900 python3 scripts/pos_app_e2e.py
