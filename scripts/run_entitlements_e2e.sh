#!/bin/bash
# Task 15 repro run: restart PG-safe backend on :8080 and run the
# entitlements e2e. Backgrounds die between bash calls → single call.
export PATH=/tmp/gotool/bin:$PATH GOPATH=/tmp/gopath GOCACHE=/tmp/gocache GOTOOLCHAIN=local
export DATABASE_URL='postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable'
export BOOTSTRAP_SUPER_ADMIN_EMAIL=e2e-admin@pharmacyos.test
export BOOTSTRAP_SUPER_ADMIN_PASSWORD='E2eAdmin#2026'
export PORT=8080 APP_ENV=development

/tmp/pg17/bin/pg_ctl -D /home/z/pgdata -l /tmp/pglog/pg.log status >/dev/null 2>&1 \
  || /tmp/pg17/bin/pg_ctl -D /home/z/pgdata -l /tmp/pglog/pg.log start >/dev/null 2>&1
sleep 1

pkill -f 'pharmacy-backend$' 2>/dev/null
sleep 0.5
/tmp/pharmacy-backend > /tmp/pharmacy-backend.log 2>&1 &
BACKPID=$!

for i in $(seq 1 60); do
  curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 && break
  sleep 0.5
done

echo "=== health ==="
curl -s http://127.0.0.1:8080/health
echo
echo "=== migrations applied ==="
python3 -c "
import psycopg2
conn = psycopg2.connect('host=127.0.0.1 port=54329 dbname=reports_test user=postgres')
cur = conn.cursor()
cur.execute(\"SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 3\")
print(cur.fetchall())
conn.close()"

echo "=== e2e ==="
cd /home/z/my-project/pharmacy-public
python3 scripts/company_entitlements_e2e.py
E2E=$?
echo "=== drift guard check (startup log) ==="
rg -n "PLANS|migration" /tmp/pharmacy-backend.log | head -5
kill $BACKPID 2>/dev/null
exit $E2E
