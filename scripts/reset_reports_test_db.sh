#!/usr/bin/env bash
# إعادة ضبط قاعدة الاختبار reports_test إلى سيناريو print_seed (الأساس لكل السويتات)
# تُستدعى من run_permissions_regression.sh لضمان تكرارية التشغيل على نفس البيئة.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="/home/z/.venv/bin:$PATH"
export GOTOOLCHAIN=auto CGO_ENABLED=0 GOFLAGS=-mod=vendor
export DATABASE_URL="postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable"

echo "== Reset: stop backend =="
pkill -f pharmacy-backend 2>/dev/null; sleep 1

echo "== Reset: drop & recreate =="
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

echo "== Reset: backend up (auto-migrate) =="
(cd backend && /tmp/go/bin/go build -o /tmp/pharmacy-backend ./cmd/server) || exit 1
setsid nohup /tmp/pharmacy-backend > /tmp/backend.log 2>&1 &
for _ in $(seq 1 60); do curl -s -o /dev/null --max-time 2 http://localhost:8080/api/v1/health && break; sleep 0.5; done
curl -s -o /dev/null -w "backend health: %{http_code}\n" --max-time 3 http://localhost:8080/api/v1/health

echo "== Reset: seed base scenario =="
python3 scripts/print_seed.py > /tmp/print_seed.log 2>&1 || { echo "print_seed FAILED"; tail -5 /tmp/print_seed.log; exit 1; }
grep -cE "product: (200|201)" /tmp/print_seed.log | xargs echo "print_seed products created:"
python3 scripts/seed_search_fixtures.py > /tmp/seed_fixtures.log 2>&1 || { echo "seed_fixtures FAILED"; tail -5 /tmp/seed_fixtures.log; exit 1; }
tail -1 /tmp/seed_fixtures.log

python3 - <<'PY'
import psycopg2
conn = psycopg2.connect("postgresql://postgres@127.0.0.1:54329/reports_test")
cur = conn.cursor()
cur.execute("SELECT count(*) FROM global_products WHERE name='مرهم جروح'")
print("مرهم جروح:", cur.fetchone()[0])
cur.execute("SELECT count(*) FROM permissions")
print("permissions:", cur.fetchone()[0])
PY
echo "RESET DONE"
