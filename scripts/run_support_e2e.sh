#!/usr/bin/env bash
# E2E — نظام الدعم (دردشة حية + تذاكر، المرحلة T1): قاعدة نظيفة + سوكيت حي.
# كل شيء في نفس استدعاء shell (الخلفيات تُقتل بين الاستدعاءات).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export PATH="/tmp/gotool/bin:$PATH" GOPATH=/tmp/gopath GOCACHE=/tmp/gocache GOTOOLCHAIN=local GOFLAGS=-mod=vendor
export DATABASE_URL="postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable"
export BOOTSTRAP_SUPER_ADMIN_EMAIL=e2e-admin@pharmacyos.test
export BOOTSTRAP_SUPER_ADMIN_PASSWORD='E2eAdmin#2026'
export PORT=8080 APP_ENV=development

echo "== PostgreSQL =="
LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata status >/dev/null 2>&1 \
  || LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata -o "-p 54329 -k /tmp" -l /home/z/pgdata/log.txt start >/dev/null 2>&1
sleep 1

echo "== Reset: reports_test نظيفة =="
python3 - <<'PY'
import psycopg2
conn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/postgres")
conn.autocommit = True
cur = conn.cursor()
cur.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='reports_test' AND pid <> pg_backend_pid()")
cur.execute("DROP DATABASE IF EXISTS reports_test")
cur.execute("CREATE DATABASE reports_test")
cur.execute("SELECT 1 FROM pg_database WHERE datname='reports_test'")
assert cur.fetchone(), "reports_test missing after create"
print("reports_test recreated (fresh)")
PY

echo "== بناء الباكند =="
(cd backend && go build -o /tmp/pharmacy-backend ./cmd/server) || exit 1
pkill -f 'pharmacy-backend$' 2>/dev/null; sleep 0.5

echo "== تشغيل الباكند على 8080 =="
export PUBLIC_APP_URL=http://localhost:3000
setsid nohup /tmp/pharmacy-backend > /tmp/backend_support_e2e.log 2>&1 &
for _ in $(seq 1 60); do
  curl -s -o /dev/null --max-time 2 http://localhost:8080/api/v1/health && break
  sleep 0.5
done
curl -s http://localhost:8080/api/v1/health | head -c 200; echo

echo "== E2E: Support Live Chat + Tickets =="
/home/z/.venv/bin/python3 scripts/support_e2e.py
STATUS=$?

pkill -f 'pharmacy-backend$' 2>/dev/null
[ $STATUS -eq 0 ] && echo "SUPPORT E2E OK" || echo "SUPPORT E2E FAILED"
exit $STATUS
