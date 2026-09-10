#!/usr/bin/env bash
# dev-up.sh — تشغيل كل الخدمات داخل نفس استدعاء shell (قاعدة البيئة: الخلفيات
# تُقتل بين الاستدعاءات). يُستخدم هكذا:
#   bash scripts/dev-up.sh && bash scripts/run_receipt_e2e.sh
# أو مع أمر مخصص:
#   bash scripts/dev-up.sh "python3 scripts/some_test.py"
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# بايثون البيئة المحلية (requests/openpyxl/playwright) داخل أوامر bash -lc
export PATH="/home/z/.venv/bin:$PATH"

PG=/tmp/pg17/bin
PGDATA=/home/z/pgdata
export DATABASE_URL="${E2E_DATABASE_URL:-postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable}"
export LD_LIBRARY_PATH=/tmp/pg17/lib

start_pg() {
  "$PG/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1 && return 0
  "$PG/pg_ctl" -D "$PGDATA" -o "-p 54329 -k /tmp" -l "$PGDATA/log.txt" start >/dev/null 2>&1
  for _ in $(seq 1 20); do
    "$PG/pg_isready" -h 127.0.0.1 -p 54329 >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  echo "PG failed to start"; return 1
}

start_backend() {
  # اقتل أي نسخة قديمة ثم أعد البناء لو الكود أحدث من الثنائي
  pkill -f pharmacy-backend 2>/dev/null; sleep 0.5
  if [ -x /tmp/pharmacy-backend ]; then
    STALE=$(find backend internal -name "*.go" -newer /tmp/pharmacy-backend 2>/dev/null | head -1)
    [ -n "$STALE" ] && rm -f /tmp/pharmacy-backend
  fi
  [ -x /tmp/pharmacy-backend ] || (cd backend && GOTOOLCHAIN=auto CGO_ENABLED=0 GOFLAGS=-mod=vendor /tmp/go/bin/go build -o /tmp/pharmacy-backend ./cmd/server) || return 1
  setsid nohup /tmp/pharmacy-backend > /tmp/backend.log 2>&1 &
  for _ in $(seq 1 60); do
    curl -s -o /dev/null --max-time 2 http://localhost:8080/api/v1/health && return 0
    sleep 0.5
  done
  echo "backend failed"; tail -5 /tmp/backend.log; return 1
}

start_frontend() {
  curl -s -o /dev/null --max-time 3 http://localhost:3000/login && return 0
  (cd frontend/apps/pharmacy-app && setsid nohup npm run dev > /tmp/frontend.log 2>&1 &)
  for _ in $(seq 1 60); do
    curl -s -o /dev/null --max-time 3 http://localhost:3000/login && return 0
    sleep 1
  done
  echo "frontend failed"; tail -5 /tmp/frontend.log; return 1
}

start_pg || exit 1
start_backend || exit 1
start_frontend || exit 1
echo "services up: pg:54329 backend:8080 frontend:3000"

# إن مُرّر أمر يُنفَّذ بعد جاهزية الخدمات (بدون login shell كي لا يُعاد ضبط PATH)
if [ $# -gt 0 ]; then
  "$@"
  STATUS=$?
  exit $STATUS
fi
