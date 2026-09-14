#!/usr/bin/env bash
# تشغيل e2e المرحلة 2 (استيراد الصيدليات ومزامنتها) في استدعاء shell واحد.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export PATH="/home/z/.venv/bin:$PATH"
export GOTOOLCHAIN=auto CGO_ENABLED=0 GOFLAGS=-mod=vendor
export DATABASE_URL="${E2E_DATABASE_URL:-postgresql://postgres@127.0.0.1:54329/reports_test?sslmode=disable}"
export BOOTSTRAP_SUPER_ADMIN_EMAIL="${BOOTSTRAP_SUPER_ADMIN_EMAIL:-admin@pharmacy-os.test}"
export BOOTSTRAP_SUPER_ADMIN_PASSWORD="${BOOTSTRAP_SUPER_ADMIN_PASSWORD:-Str0ng!Admin2026}"
LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata status >/dev/null 2>&1 \
  || LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_ctl -D /home/z/pgdata -o "-p 54329 -k /tmp" -l /home/z/pgdata/log.txt start >/dev/null 2>&1
for _ in $(seq 1 20); do
  LD_LIBRARY_PATH=/tmp/pg17/lib /tmp/pg17/bin/pg_isready -h 127.0.0.1 -p 54329 >/dev/null 2>&1 && break
  sleep 0.5
done

echo "== بناء الباكند =="
(cd backend && /tmp/gotool/bin/go build -o /tmp/pharmacy-backend ./cmd/server) || exit 1
pkill -f pharmacy-backend 2>/dev/null; sleep 0.5

echo "== تشغيل الباكند على 8080 =="
setsid nohup /tmp/pharmacy-backend > /tmp/backend.log 2>&1 &
for _ in $(seq 1 60); do
  curl -s -o /dev/null --max-time 2 http://localhost:8080/api/v1/health && break
  sleep 0.5
done
curl -s -w " <- health\n" --max-time 3 http://localhost:8080/api/v1/health

echo "== E2E P2: استيراد المكتبات ومزامنتها =="
python3 scripts/libraries_p2_e2e.py
STATUS=$?

pkill -f pharmacy-backend 2>/dev/null
exit $STATUS
